//
// BXPGDatabaseDescription.m
// BaseTen
//
// Copyright (C) 2006-2009 Marko Karppinen & Co. LLC.
//
// Before using this software, please review the available licensing options
// by visiting http://basetenframework.org/licensing/ or by contacting
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

#import "BXPGDatabaseDescription.h"
#import "BXLogger.h"
#import "PGTSConnection.h"
#import "PGTSResultSet.h"
#import "BXPGTableDescription.h"
#import "BXPGForeignKeyDescription.h"

namespace PGTS 
{
	void InsertConditionally (IdentifierMap* map, BXPGForeignKeyDescription* description);
}

void PGTS::InsertConditionally (IdentifierMap* map, BXPGForeignKeyDescription* description)
{
	NSInteger identifier = [description identifier];
	if (! (* map) [identifier])
		(* map) [identifier] = [description retain];	
}


using namespace PGTS;

@implementation BXPGDatabaseDescription
- (id) init
{
	if ((self = [super init]))
	{
		mForeignKeysByIdentifier = new IdentifierMap ();
	}
	return self;
}

- (void) dealloc
{
	[mSchemaVersion release];
	[mSchemaCompatibilityVersion release];
	for (IdentifierMap::const_iterator it = mForeignKeysByIdentifier->begin (), end = mForeignKeysByIdentifier->end (); 
		 it != end; it++)
	{
		[it->second release];
	}
	
	delete mForeignKeysByIdentifier;
	[super dealloc];
}

- (void) finalize
{
	delete mForeignKeysByIdentifier;
	[super finalize];
}

- (BOOL) hasBaseTenSchema
{
	return mHasBaseTenSchema;
}

- (NSNumber *) schemaVersion
{
	return mSchemaVersion;
}

- (NSNumber *) schemaCompatibilityVersion
{
	return mSchemaCompatibilityVersion;
}

- (void) setSchemaVersion: (NSNumber *) number
{
	if (mSchemaVersion != number)
	{
		[mSchemaVersion release];
		mSchemaVersion = [number retain];
	}
}

- (void) setSchemaCompatibilityVersion: (NSNumber *) number
{
	if (mSchemaCompatibilityVersion != number)
	{
		[mSchemaCompatibilityVersion release];
		mSchemaCompatibilityVersion = [number retain];
	}
}

- (void) setHasBaseTenSchema: (BOOL) aBool
{
	mHasBaseTenSchema = aBool;
}

- (void) addForeignKey: (BXPGForeignKeyDescription *) fkey
{
	InsertConditionally (mForeignKeysByIdentifier, fkey);
}

- (BXPGForeignKeyDescription *) foreignKeyWithIdentifier: (NSInteger) identifier
{
	return FindObject (mForeignKeysByIdentifier, identifier);
}
@end
