//
// PGTSDatabaseInfo.m
// BaseTen
//
// Copyright (C) 2006 Marko Karppinen & Co. LLC.
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

#import <PGTS/PGTSDatabaseInfo.h>
#import <PGTS/PGTSTypeInfo.h>
#import <PGTS/PGTSTableInfo.h>
#import <PGTS/PGTSResultSet.h>
#import <PGTS/PGTSConnection.h>
#import <PGTS/PGTSAdditions.h>
#import <TSDataTypes/TSDataTypes.h>


#define AddClass( CLASSNAME, ARRAY ) { \
    CLASSNAME* rval = nil; \
    if (InvalidOid != anOid) \
    { \
        rval = [ARRAY objectAtIndex: anOid]; \
        if (nil == rval) \
        { \
            rval = [[CLASSNAME alloc] initWithConnection: connection]; \
            [rval setOid: anOid]; \
            [rval setDatabase: self]; \
            [ARRAY setObject: rval atIndex: anOid]; \
            [rval release]; \
        } \
    } \
    return rval; \
}
    

/** 
 * Database
 */
@implementation PGTSDatabaseInfo

- (BOOL) schemaExists: (NSString *) schemaName
{
    BOOL rval = YES;
    if (nil == [schemas objectForKey: schemaName])
    {
        NSString* query = @"SELECT oid FROM pg_namespace WHERE nspname = $1";
        PGTSResultSet* res = [connection executeQuery: query parameters: schemaName];
        NSAssert ([res querySucceeded], nil);
        if (0 == [res countOfRows])
            rval = NO;
        else
        {
            NSMutableDictionary* schema = [NSMutableDictionary dictionary];
            [schemas setObject: schema forKey: schemaName];
        }
    }
    return rval;
}

- (id) initWithConnection: (PGTSConnection *) aConnection
{
    if ((self = [super initWithConnection: aConnection]))
    {
        tables = [[TSIndexDictionary alloc] init];
        types  = [[TSIndexDictionary alloc] init];
        schemas = [[NSMutableDictionary alloc] init];
        roles = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void) dealloc
{
    [tables makeObjectsPerformSelector: @selector (setDatabase:) withObject: nil];
    [types  makeObjectsPerformSelector: @selector (setDatabase:) withObject: nil];
    
    [tables release];
    [types release];
    [schemas release];
    [connectionPoolKey release];
    [roles release];
    [super dealloc];
}

- (PGTSTableInfo *) tableInfoForTableWithOid: (Oid) anOid
{
    AddClass (PGTSTableInfo, tables);
}

- (PGTSTypeInfo *) typeInfoForTypeWithOid: (Oid) anOid
{
    AddClass (PGTSTypeInfo, types);
}

- (PGTSTableInfo *) tableInfoForTableNamed: (NSString *) tableName inSchemaNamed: (NSString *) schemaName
{
    if (nil == schemaName || 0 == [schemaName length])
        schemaName = @"public";
    PGTSTableInfo* rval = [[schemas objectForKey: schemaName] objectForKey: tableName];
    if (nil == rval)
    {
        NSString* queryString = @"SELECT c.oid AS oid, c.relnamespace AS schemaoid FROM pg_class c, pg_namespace n WHERE c.relname = $1 AND n.nspname = $2";
        PGTSResultSet* res = [connection executeQuery: queryString parameters: tableName, schemaName];
        if (0 < [res countOfRows])
        {
            [res advanceRow];
            rval = [self tableInfoForTableWithOid: [[res valueForKey: @"oid"] PGTSOidValue]];
            [rval setName: tableName];
            [rval setSchemaOid: [[res valueForKey: @"schemaoid"] PGTSOidValue]];
            [rval setSchemaName: schemaName];
            [self updateTableCache: rval];
        }
    }
    return rval;
}

- (void) updateTableCache: (PGTSTableInfo *) table
{
    if (nil != table)
    {
        NSString* schemaName = [table schemaName];
        NSMutableDictionary* schema = [schemas objectForKey: schemaName];
        if (nil == schema)
        {
            schema = [NSMutableDictionary dictionary];
            [schemas setObject: schema forKey: schemaName];
        }
        [schema setObject: table forKey: [table name]];
    }
}

- (NSString *) connectionPoolKey;
{
    return connectionPoolKey;
}

- (void) setConnectionPoolKey: (NSString *) aKey
{
    if (connectionPoolKey != aKey)
    {
        [connectionPoolKey release];
        aKey = [connectionPoolKey retain];
    }
}

@end
