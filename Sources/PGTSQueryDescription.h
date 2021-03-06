//
// PGTSQueryDescription.h
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

#import <Foundation/Foundation.h>
@class PGTSQuery;
@class PGTSConnection;
@class PGTSResultSet;


@interface PGTSQueryDescription : NSObject
{
}
- (SEL) callback;
- (void) setCallback: (SEL) aSel;
- (id) delegate;
- (void) setDelegate: (id) anObject;
- (NSInteger) identifier;
- (PGTSQuery *) query;
- (void) setQuery: (PGTSQuery *) aQuery;
- (void) setUserInfo: (id) userInfo;
- (BOOL) sent;
- (BOOL) finished;

- (int) sendForConnection: (PGTSConnection *) connection;
- (PGTSResultSet *) receiveForConnection: (PGTSConnection *) connection;
- (PGTSResultSet *) finishForConnection: (PGTSConnection *) connection;

@end


@interface PGTSConcreteQueryDescription : PGTSQueryDescription
{
	SEL mCallback;
	id mDelegate; //Weak
	NSInteger mIdentifier;
	PGTSQuery* mQuery;
	id mUserInfo;
	BOOL mSent;
	BOOL mFinished;
}
@end