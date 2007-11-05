//
// ObjectTests.m
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

#import "ObjectTests.h"
#import "MKCSenTestCaseAdditions.h"

#import <OCMock/OCMock.h>
#import <BaseTen/BaseTen.h>
#import <BaseTen/BXDatabaseObjectPrivate.h>
#import <BaseTen/BXDatabaseContextPrivate.h>


@interface TestAttDesc : NSObject
{
    @public
    NSString* mName;
    BOOL mIsPkey;
    BOOL mIsOptional;
}
@end

@implementation TestAttDesc
+ (id) t
{
    return [[[self alloc] init] autorelease];
}
- (void) dealloc
{
    [mName release];
    [super dealloc];
}
- (NSString *) name
{
    return mName;
}
- (NSComparisonResult) compare: (id) anObject
{
    return [mName compare: anObject];
}
- (BOOL) isPrimaryKey
{
    return mIsPkey;
}
- (BOOL) isOptional
{
    return mIsOptional;
}
@end


@implementation ObjectTests
- (void) setUp
{
    TestAttDesc* idDesc = [TestAttDesc t];
    idDesc->mName = @"id";
    idDesc->mIsPkey = YES;
    idDesc->mIsOptional = NO;
    
    TestAttDesc* keyDesc = [TestAttDesc t];
    keyDesc->mName = @"key";
    keyDesc->mIsPkey = NO;
    keyDesc->mIsOptional = YES;
    
    mContext = [OCMockObject niceMockForClass: [BXDatabaseContext class]];
    [[[mContext stub] andReturnValue: [NSNumber numberWithBool: YES]] registerObject: mObject];

    mEntity = [OCMockObject niceMockForClass: [BXEntityDescription class]];
    [[[mEntity stub] andReturn: [NSArray arrayWithObject: idDesc]] primaryKeyFields];
    [[[mEntity stub] andReturn: [NSDictionary dictionaryWithObjectsAndKeys:
        idDesc, @"id",
        keyDesc, @"key",
        nil]] attributesByName];
    [[[mEntity stub] andReturnValue: [NSNumber numberWithBool: YES]] isValidated];
    
    mObject = [[BXDatabaseObject alloc] init];
    MKCAssertNotNil (mObject);
    [mObject setCachedValue: @"value" forKey: @"key"];
    [mObject setCachedValue: [NSNumber numberWithInt: 1] forKey: @"id"];
}

- (void) tearDown
{
    [mContext verify];
    [mEntity verify];    
    
    [mObject release];
}

- (void) testCachedValue
{    
    MKCAssertEqualObjects (@"value", [mObject cachedValueForKey: @"key"]);
}

- (void) testRegistrationPrimitiveAndFault
{
    //Registration
    [mObject registerWithContext: mContext entity: mEntity];

    //Primitive
    MKCAssertEqualObjects ([NSNumber numberWithInt: 1], 
                           [mObject primitiveValueForKey: @"id"]);
    
    //Fault
    MKCAssertTrue (0 == [mObject isFaultKey: @"id"]);
    MKCAssertTrue (0 == [mObject isFaultKey: @"key"]);
}

- (void) testFaultingAndObserving
{    
    //We need an objectID for -[BXDatabaseObject isEqual:].
    [mObject registerWithContext: mContext entity: mEntity];

    id observer = [OCMockObject mockForClass: [NSObject class]];
    [[observer expect] observeValueForKeyPath: @"key" ofObject: mObject change: OCMOCK_ANY context: OCMOCK_ANY];

    MKCAssertTrue (0 == [mObject isFaultKey: @"key"]);
    [mObject addObserver: observer forKeyPath: @"key" options: 0 context: NULL];
    [mObject faultKey: @"key"];
    //We'd require an object id for testing 0 == isFaultKey.
    MKCAssertTrue (-1 == [mObject isFaultKey: @"key"]);
    
    [observer verify];
}

- (void) testNullValidation
{
    //We need an entity for this.
    [mObject registerWithContext: mContext entity: mEntity];
    
    id value = nil;
    NSError* error = nil;
    MKCAssertFalse ([mObject validateValue: &value forKey: @"id" error: &error]);
    MKCAssertNotNil (error);
    
    error = nil;
    MKCAssertTrue ([mObject validateValue: &value forKey: @"key" error: &error]);
    STAssertNil (error, [error localizedDescription]);
}
@end
