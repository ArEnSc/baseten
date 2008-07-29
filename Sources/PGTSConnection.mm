//
// PGTSConnection.mm
// BaseTen
//
// Copyright (C) 2008 Marko Karppinen & Co. LLC.
//
// Before using this software, please review the available licensing options
// by visiting http://www.karppinen.fi/baseten/licensing/ or by contacting
// us at sales@karppinen.fi. Without an additional license, this software
// may be distributed only in compliance with the GNU General Public License.
//
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License, version 2.0,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
//
// $Id$
//

#import <CoreFoundation/CoreFoundation.h>
#import <AppKit/AppKit.h>
#import "postgresql/libpq-fe.h"

#import "PGTSConnection.h"
#import "PGTSConnectionPrivate.h"
#import "PGTSConnector.h"
#import "PGTSConstants.h"
#import "PGTSQuery.h"
#import "PGTSQueryDescription.h"
#import "PGTSAdditions.h"
#import "PGTSResultSet.h"
#import "PGTSDatabaseDescription.h"
#import "PGTSFunctions.h"
#import "PGTSConnectionMonitor.h"
#import "PGTSNotification.h"
#import "PGTSProbes.h"
#import "BXLogger.h"
#import "libpq_additions.h"


@interface PGTSConnection (PGTSConnectorDelegate) <PGTSConnectorDelegate>
- (void) connector: (PGTSConnector*) connector gotConnection: (PGconn *) connection succeeded: (BOOL) succeeded;
@end



@implementation PGTSConnection

static void
NoticeReceiver (void* connectionPtr, const PGresult* notice)
{
	PGTSConnection* connection = (PGTSConnection *) connectionPtr;
	NSError* error = [PGTSResultSet errorForPGresult: notice];
	[connection->mDelegate PGTSConnection: connection receivedNotice: error];
}


static void
SocketReady (CFSocketRef s, CFSocketCallBackType callbackType, CFDataRef address, const void* data, void* self)
{
	if (kCFSocketReadCallBack & callbackType)
	{
		[(id) self readFromSocket];
	}
}


+ (void) initialize
{
	static BOOL tooLate = NO;
	if (! tooLate)
	{
		tooLate = YES;
		
		{
            NSMutableArray* keys = [[NSMutableArray alloc] init];
			CFRetain (keys);
            PQconninfoOption *option = PQconndefaults ();
            char* keyword = NULL;
            while ((keyword = option->keyword))
            {
                NSString* key = [NSString stringWithUTF8String: keyword];
                [keys addObject: key];
                option++;
            }
			kPGTSConnectionDictionaryKeys = keys;
		}
	}
}


- (id) init
{
	if ((self = [super init]))
	{
		mQueue = [[NSMutableArray alloc] init];
		mCertificateVerificationDelegate = [PGTSCertificateVerificationDelegate defaultCertificateVerificationDelegate];
	}
	return self;
}

- (void) freeCFTypes
{
	//Don't release the connection. Delegate will handle it.
	if (mSocketSource)
	{
		CFRunLoopSourceInvalidate (mSocketSource);
		CFRelease (mSocketSource);
		mSocketSource = NULL;
	}
	
	if (mSocket)
	{
		CFSocketInvalidate (mSocket);
		CFRelease (mSocket);
		mSocket = NULL;
	}
	
	if (mRunLoop)
	{
		CFRelease (mRunLoop);
		mRunLoop = NULL;
	}
}

- (void) dealloc
{
	[[PGTSConnectionMonitor sharedInstance] unmonitorConnection: self];
    [self disconnect];
	[mQueue release];
	[self setConnector: nil];
    [mDatabase release];
	[mPGTypes release];
    [self freeCFTypes];
	[super dealloc];
}

- (void) finalize
{
    [self disconnect];
    [self freeCFTypes];
    [super finalize];
}

- (BOOL) connectUsingClass: (Class) connectorClass connectionString: (NSString *) connectionString
{
	PGTSConnector* connector = [[connectorClass alloc] init];
	[self setConnector: connector];
	[connector release];
	
	[connector setConnection: mConnection];
	[connector setDelegate: self];
	[connector setTraceFile: [mDelegate PGTSConnectionTraceFile: self]];
	[[PGTSConnectionMonitor sharedInstance] monitorConnection: self];
	return [connector connect: [connectionString UTF8String]];
}

- (void) connectAsync: (NSString *) connectionString
{
	[self connectUsingClass: [PGTSAsynchronousConnector class] connectionString: connectionString];
}

- (BOOL) connectSync: (NSString *) connectionString
{
	return [self connectUsingClass: [PGTSSynchronousConnector class] connectionString: connectionString];
}

- (void) resetAsync
{
	[self connectUsingClass: [PGTSAsynchronousReconnector class] connectionString: nil];
}

- (BOOL) resetSync
{
	return [self connectUsingClass: [PGTSSynchronousReconnector class] connectionString: nil];
}

- (void) disconnect
{
    BXLogInfo (@"Disconnecting.");
    [mConnector cancel];
    if (mConnection)
    {
        PQfinish (mConnection);
        mConnection = NULL;
    }
}

- (PGconn *) pgConnection
{
    return mConnection;
}

- (void) setConnector: (PGTSConnector *) anObject
{
	if (mConnector != anObject)
	{
		[mConnector autorelease];
		mConnector = [anObject retain];
	}
}

- (void) readFromSocket
{
	//When the socket is ready for read, send any available notifications and read results until 
	//the socket blocks. If all results for the current query have been read, send the next query.
	PQconsumeInput (mConnection);
    
    [self processNotifications];
	
	if (0 < [mQueue count])
	{
		PGTSQueryDescription* queryDescription = [[[mQueue objectAtIndex: 0] retain] autorelease];
		while (! PQisBusy (mConnection))
		{
			[queryDescription receiveForConnection: self];
			if ([queryDescription finished])
				break;
		}
		
		if ([queryDescription finished])
		{
			unsigned int count = [mQueue count];
			if (count)
			{
				if ([mQueue objectAtIndex: 0] == queryDescription)
				{
					[mQueue removeObjectAtIndex: 0];
					count--;
				}
				
				if (count)
					[self sendNextQuery];
			}            
		}
	}
}

- (void) processNotifications
{
	//Notifications may cause methods to be called. They might require a specific order
	//(e.g. self-updating collections in BaseTen), which breaks if this is called recursively.
	//Hence we prevent it.
	if (! mProcessingNotifications)
	{
		mProcessingNotifications = YES;
		PGnotify* pgNotification = NULL;
		while ((pgNotification = PQnotifies (mConnection)))
		{
			NSString* name = [NSString stringWithUTF8String: pgNotification->relname];
			PGTSNotification* notification = [[[PGTSNotification alloc] init] autorelease];
			[notification setBackendPID: pgNotification->be_pid];
			[notification setNotificationName: name];
			PGTS_RECEIVED_NOTIFICATION (self, pgNotification->be_pid, pgNotification->relname, pgNotification->extra);		
			PQfreeNotify (pgNotification);
			[mDelegate PGTSConnection: self gotNotification: notification];
		}    
		mProcessingNotifications = NO;
	}
}

- (int) sendNextQuery
{
	int retval = -1;
	PGTSQueryDescription* desc = [mQueue objectAtIndex: 0];
	if (nil != desc)
	{
		BXAssertValueReturn (! [desc sent], retval, @"Expected %@ not to have been sent.", desc);	
		retval = [desc sendForConnection: self];
		
		[self checkConnectionStatus];
	}
    return retval;
}

- (int) sendOrEnqueueQuery: (PGTSQueryDescription *) query
{
	int retval = -1;
	[mQueue addObject: query];
	if (1 == [mQueue count] && mConnection)
		retval = [self sendNextQuery];
	return retval;
}

- (void) setDelegate: (id <PGTSConnectionDelegate>) anObject
{
    mDelegate = anObject;
}

- (PGTSDatabaseDescription *) databaseDescription
{
    if (! mDatabase)
    {
		mDatabase = [[PGTSDatabaseDescription databaseForConnection: self] retain];
    }
    return mDatabase;
}

- (void) setDatabaseDescription: (PGTSDatabaseDescription *) aDesc
{
    if (mDatabase != aDesc)
    {
        [mDatabase release];
		mDatabase = [[aDesc proxyForConnection: self] retain];
    }
}

- (id) deserializationDictionary
{
    if (! mPGTypes)
    {
		NSBundle* bundle = [NSBundle bundleForClass: [PGTSConnection class]];
        NSString* path = [[bundle resourcePath] stringByAppendingString: @"/datatypeassociations.plist"];
        NSData* plist = [NSData dataWithContentsOfFile: path];
        BXAssertValueReturn (nil != plist, nil, @"datatypeassociations.plist was not found (looked from %@).", path);
        NSString* error = nil;
        mPGTypes = [[NSPropertyListSerialization propertyListFromData: plist mutabilityOption: NSPropertyListMutableContainers
                                                               format: NULL errorDescription: &error] retain];
        BXAssertValueReturn (nil != mPGTypes, nil, @"Error creating PGTSDeserializationDictionary: %@ (file: %@)", error, path);
        NSArray* keys = [mPGTypes allKeys];
        TSEnumerate (key, e, [keys objectEnumerator])
        {
            Class typeClass = NSClassFromString ([mPGTypes objectForKey: key]);
            if (Nil == typeClass)
                [mPGTypes removeObjectForKey: key];
            else
                [mPGTypes setObject: typeClass forKey: key];
        }
    }
    return mPGTypes;
}

- (NSString *) errorString
{
	return [NSString stringWithUTF8String: PQerrorMessage (mConnection)];
}

- (NSError *) connectionError
{
	//This becomes unavailable after the delegate method call because the connector gets set to nil.
	enum PGTSConnectionError code = kPGTSConnectionErrorNone;
	BOOL SSLAttempted = [mConnector SSLSetUp];
	const char* SSLMode = pq_ssl_mode (mConnection);
	
	if (! SSLAttempted && 0 == strcmp ("require", SSLMode))
		code = kPGTSConnectionErrorSSLUnavailable;
	else if (PQconnectionNeedsPassword (mConnection))
		code = kPGTSConnectionErrorPasswordRequired;
	else if (PQconnectionUsedPassword (mConnection))
		code = kPGTSConnectionErrorInvalidPassword;
	else
		code = kPGTSConnectionErrorUnknown;
	
	NSError* retval = [NSError errorWithDomain: kPGTSConnectionErrorDomain code: code userInfo: nil];
	return retval;
	return nil;
}

- (id <PGTSCertificateVerificationDelegate>) certificateVerificationDelegate
{
	return mCertificateVerificationDelegate;
}

- (void) setCertificateVerificationDelegate: (id <PGTSCertificateVerificationDelegate>) anObject
{
	mCertificateVerificationDelegate = anObject;
	if (! mCertificateVerificationDelegate)
		mCertificateVerificationDelegate = [PGTSCertificateVerificationDelegate defaultCertificateVerificationDelegate];
}

- (void) applicationWillTerminate: (NSNotification *) n
{
    [self disconnect];
}

- (void) workspaceWillSleep: (NSNotification *) n
{
 	[self disconnect];
	mDidDisconnectOnSleep = YES;
}

- (void) workspaceDidWake: (NSNotification *) n
{
	if (mDidDisconnectOnSleep)
	{
		mDidDisconnectOnSleep = NO;
		[mDelegate PGTSConnectionLost: self error: nil]; //FIXME: set the error.
	}
}

- (void) checkConnectionStatus
{
	if (CONNECTION_BAD == PQstatus (mConnection))
		[mDelegate PGTSConnectionLost: self error: nil]; //FIXME: set the error.
	//FIXME: also indicate that a reset will be sufficient instead of reconnecting.
}

- (ConnStatusType) connectionStatus
{
	return PQstatus (mConnection);
}

- (PGTransactionStatusType) transactionStatus
{
	return PQtransactionStatus (mConnection);
}

- (int) backendPID
{
	return PQbackendPID (mConnection);
}

- (PGresult *) execQuery: (const char *) query
{
	if (mLogsQueries)
		[mDelegate PGTSConnection: self sentQueryString: query];
	
	PGresult* res = PQexec (mConnection, query);
	if (PGTS_SEND_QUERY_ENABLED ())
	{
		char* query_s = strdup (query);
		PGTS_SEND_QUERY (self, 1, query_s, NULL);
		free (query_s);
	}
	
	return res;
}

- (id <PGTSConnectionDelegate>) delegate
{
	return mDelegate;
}

- (BOOL) logsQueries
{
	return mLogsQueries;
}

- (void) setLogsQueries: (BOOL) flag
{
	mLogsQueries = flag;
}
@end


@implementation PGTSConnection (PGTSConnectorDelegate)
- (void) connector: (PGTSConnector*) connector gotConnection: (PGconn *) connection succeeded: (BOOL) succeeded
{
	mConnection = connection;
	if (succeeded)
	{
		//Rather than call PQsendquery etc. multiple times, monitor the socket state.
		PQsetnonblocking (connection, 0); 
		//Use UTF-8.
        PQsetClientEncoding (connection, "UNICODE"); 
		[self execQuery: "SET standard_conforming_strings TO true"];
		[self execQuery: "SET datestyle TO 'ISO, YMD'"];
		PQsetNoticeReceiver (connection, &NoticeReceiver, (void *) self);
        //FIXME: set other things as well?
		
		//Create a runloop source to receive data asynchronously.
		CFSocketContext context = {0, self, NULL, NULL, NULL};
		CFSocketCallBackType callbacks = (CFSocketCallBackType)(kCFSocketReadCallBack | kCFSocketWriteCallBack);
		mSocket = CFSocketCreateWithNative (NULL, PQsocket (mConnection), callbacks, &SocketReady, &context);
        
		CFOptionFlags flags = ~kCFSocketCloseOnInvalidate & CFSocketGetSocketFlags (mSocket);
		CFSocketSetSocketFlags (mSocket, flags);
		mSocketSource = CFSocketCreateRunLoopSource (NULL, mSocket, 0);
		
		BXAssertLog (mSocket, @"Expected source to have been created.");
		BXAssertLog (CFSocketIsValid (mSocket), @"Expected socket to be valid.");
		BXAssertLog (mSocketSource, @"Expected socketSource to have been created.");
		BXAssertLog (CFRunLoopSourceIsValid (mSocketSource), @"Expected socketSource to be valid.");
		
        CFRunLoopRef runloop = mRunLoop ?: CFRunLoopGetCurrent ();
        CFStringRef mode = kCFRunLoopCommonModes;
        CFSocketDisableCallBacks (mSocket, kCFSocketWriteCallBack);
        CFSocketEnableCallBacks (mSocket, kCFSocketReadCallBack);
        CFRunLoopAddSource (runloop, mSocketSource, mode);
        
        if (0 < [mQueue count])
            [self sendNextQuery];
        [mDelegate PGTSConnectionEstablished: self];
	}
	else
	{
		[[PGTSConnectionMonitor sharedInstance] unmonitorConnection: self];
        [mDelegate PGTSConnectionFailed: self];
	}
	[self setConnector: nil];
}

- (id <PGTSCertificateVerificationDelegate>) certificateVerificationDelegate
{
	return mCertificateVerificationDelegate;
}
@end


@implementation PGTSConnection (Queries)

#define StdargToNSArray( ARRAY_VAR, COUNT, LAST ) \
    { va_list ap; va_start (ap, LAST); ARRAY_VAR = StdargToNSArray2 (ap, COUNT, LAST); va_end (ap); }


static NSArray*
StdargToNSArray2 (va_list arguments, int argCount, id lastArg)
{
    NSMutableArray* retval = [NSMutableArray arrayWithCapacity: argCount];
	if (0 < argCount)
	{
		[retval addObject: lastArg ?: [NSNull null]];

	    for (int i = 1; i < argCount; i++)
    	{
        	id argument = va_arg (arguments, id);
	        [retval addObject: argument ?: [NSNull null]];
    	}
	}
    return retval;
}

- (PGTSResultSet *) executeQuery: (NSString *) queryString
{
	return [self executeQuery: queryString parameterArray: nil];
}

- (PGTSResultSet *) executeQuery: (NSString *) queryString parameters: (id) p1, ...
{
	NSArray* parameters = nil;
	StdargToNSArray (parameters, [queryString PGTSParameterCount], p1);
	return [self executeQuery: queryString parameterArray: parameters];
}

- (PGTSResultSet *) executeQuery: (NSString *) queryString parameterArray: (NSArray *) parameters
{
    PGTSResultSet* retval = nil;
    [self sendQuery: queryString delegate: nil callback: NULL parameterArray: parameters];
	
	PGTSQueryDescription* desc = nil;
	while (0 < [mQueue count] && (desc = [[mQueue objectAtIndex: 0] retain])) 
	{
		[mQueue removeObjectAtIndex: 0];
		retval = [desc finishForConnection: self];
		[desc release];
	}
	
    return retval;
}

- (int) sendQuery: (NSString *) queryString delegate: (id) delegate callback: (SEL) callback
{
	return [self sendQuery: queryString delegate: delegate callback: callback parameterArray: nil];
}

- (int) sendQuery: (NSString *) queryString delegate: (id) delegate callback: (SEL) callback
	   parameters: (id) p1, ...
{
	NSArray* parameters = nil;
	StdargToNSArray (parameters, [queryString PGTSParameterCount], p1);
	return [self sendQuery: queryString delegate: delegate callback: callback parameterArray: parameters];
}

- (int) sendQuery: (NSString *) queryString delegate: (id) delegate callback: (SEL) callback 
   parameterArray: (NSArray *) parameters
{
	return [self sendQuery: queryString delegate: delegate callback: callback 
			parameterArray: parameters userInfo: nil];
}

- (int) sendQuery: (NSString *) queryString delegate: (id) delegate callback: (SEL) callback 
   parameterArray: (NSArray *) parameters userInfo: (id) userInfo
{
	PGTSQueryDescription* desc = [[[PGTSConcreteQueryDescription alloc] init] autorelease];
	PGTSParameterQuery* query = [[[PGTSParameterQuery alloc] init] autorelease];
	[query setQuery: queryString];
	[query setParameters: parameters];
	[desc setQuery: query];
	[desc setDelegate: delegate];
	[desc setCallback: callback];
	[desc setUserInfo: userInfo];
	
	int retval = [desc identifier];
	[self sendOrEnqueueQuery: desc];
	return retval;
}

@end