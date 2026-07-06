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
 * Used to track a single integer statistic.
 */
public class IntStat extends Stat
{
    /**
     * Returns the value of this integer statistic.
     */
    public int getValue ()
    {
        return _value;
    }

    /**
     * Sets this statistic's value to the specified value.
     *
     * @return true if the stat was modified, false if not.
     */
    public boolean setValue (int value)
    {
        if (value != _value) {
            _value = value;
            setModified(true);
            return true;
        }
        return false;
    }

    /**
     * Increments this statistic by the specified delta value.
     *
     * @return true if the stat was modified, false if not.
     */
    public boolean increment (int delta)
    {
        return setValue(_value + delta);
    }

    @Override
    public String valueToString ()
    {
        return String.valueOf(_value);
    }

    @Override
    public void persistTo (ObjectOutputStream out, AuxDataSource aux)
        throws IOException
    {
        out.writeInt(_value);
    }

    @Override
    public void unpersistFrom (ObjectInputStream in, AuxDataSource aux)
        throws IOException, ClassNotFoundException
    {
        _value = in.readInt();
    }

    /** Contains the integer value of this statistic. */
    protected int _value;

    // from interface Streamable
    public void readObject (com.threerings.io.ObjectInputStream ins)
        throws java.io.IOException, java.lang.ClassNotFoundException
    {
        com.threerings.io.GenStreamUtil.readField(com.threerings.stats.data.Stat.class, "_type", this, ins);
        com.threerings.io.GenStreamUtil.readField(com.threerings.stats.data.Stat.class, "_modified", this, ins);
        com.threerings.io.GenStreamUtil.readField(com.threerings.stats.data.Stat.class, "_modCount", this, ins);
        com.threerings.io.GenStreamUtil.readField(com.threerings.stats.data.IntStat.class, "_value", this, ins);
    }

    // from interface Streamable
    public void writeObject (com.threerings.io.ObjectOutputStream out)
        throws java.io.IOException
    {
        com.threerings.io.GenStreamUtil.writeField(com.threerings.stats.data.Stat.class, "_type", this, out);
        com.threerings.io.GenStreamUtil.writeField(com.threerings.stats.data.Stat.class, "_modified", this, out);
        com.threerings.io.GenStreamUtil.writeField(com.threerings.stats.data.Stat.class, "_modCount", this, out);
        com.threerings.io.GenStreamUtil.writeField(com.threerings.stats.data.IntStat.class, "_value", this, out);
    }
}
