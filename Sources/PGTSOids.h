//
// PGTSOids.h
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
#import <BaseTen/BXExport.h>
#import <BaseTen/libpq-fe.h>

BX_INTERNAL id PGTSOidAsObject (Oid o);

@interface NSNumber (PGTSOidAdditions)
- (Oid) PGTSOidValue;
@end


#if defined (__cplusplus)
#import <tr1/unordered_map>
#import <BaseTen/PGTSScannedMemoryAllocator.h>

namespace PGTS 
{
	typedef std::list <Oid>
		OidList;
	
	typedef std::tr1::unordered_set <Oid>
		OidSet;
	
	typedef std::tr1::unordered_map <Oid, id, 
		std::tr1::hash <Oid>, 
		std::equal_to <Oid>, 
		PGTS::scanned_memory_allocator <std::pair <const Oid, id> > > 
		OidMap;
}

#define PGTS_OidList PGTS::OidList
#define PGTS_OidSet  PGTS::OidSet
#define PGTS_OidMap  PGTS::OidMap

#else
#define PGTS_OidList void
#define PGTS_OidSet  void
#define PGTS_OidMap  void
#endif
