//
// $Id$
//
// Vilya library - tools for developing networked games
// Copyright (C) 2002-2012 Three Rings Design, Inc., All Rights Reserved
// http://code.google.com/p/vilya/
//
// This library is free software; you can redistribute it and/or modify it
// under the terms of the GNU Lesser General Public License as published
// by the Free Software Foundation; either version 2.1 of the License, or
// (at your option) any later version.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public
// License along with this library; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

package com.threerings.stats.data;

import java.io.IOException;

import com.threerings.io.ObjectInputStream;
import com.threerings.io.ObjectOutputStream;

/**
 * A string set that maps its values to shorts.
 */
public class ShortStringSetStat extends StringSetStat
{
    @Override
    public void persistTo (ObjectOutputStream out, AuxDataSource aux)
        throws IOException
    {
        out.writeShort(_values.length);
        for (String value : _values) {
            out.writeShort((short)aux.getStringCode(_type, value));
        }
    }

    @Override
    public void unpersistFrom (ObjectInputStream in, AuxDataSource aux)
        throws IOException, ClassNotFoundException
    {
        _values = new String[in.readShort()];
        for (int ii = 0; ii < _values.length; ii++) {
            _values[ii] = aux.getCodeString(_type, in.readShort());
        }
    }

    // from interface Streamable
    public void readObject (com.threerings.io.ObjectInputStream ins)
        throws java.io.IOException, java.lang.ClassNotFoundException
    {
        com.threerings.io.GenStreamUtil.readField(com.threerings.stats.data.Stat.class, "_type", this, ins);
        com.threerings.io.GenStreamUtil.readField(com.threerings.stats.data.Stat.class, "_modified", this, ins);
        com.threerings.io.GenStreamUtil.readField(com.threerings.stats.data.Stat.class, "_modCount", this, ins);
        com.threerings.io.GenStreamUtil.readField(com.threerings.stats.data.StringSetStat.class, "_values", this, ins);
    }

    // from interface Streamable
    public void writeObject (com.threerings.io.ObjectOutputStream out)
        throws java.io.IOException
    {
        com.threerings.io.GenStreamUtil.writeField(com.threerings.stats.data.Stat.class, "_type", this, out);
        com.threerings.io.GenStreamUtil.writeField(com.threerings.stats.data.Stat.class, "_modified", this, out);
        com.threerings.io.GenStreamUtil.writeField(com.threerings.stats.data.Stat.class, "_modCount", this, out);
        com.threerings.io.GenStreamUtil.writeField(com.threerings.stats.data.StringSetStat.class, "_values", this, out);
    }
}
