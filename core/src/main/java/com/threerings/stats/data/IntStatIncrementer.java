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

/**
 * Increments a particular int stat by a specified amount.
 */
public class IntStatIncrementer extends StatModifier<IntStat>
{
    public IntStatIncrementer (Stat.Type type, int delta)
    {
        super(type);
        _delta = delta;
    }

    /** Constructs an empty IntStatIncrementer (for Streaming purposes). */
    public IntStatIncrementer ()
    {
    }

    @Override // from StatModifier
    public void modify (IntStat stat)
    {
        stat.increment(_delta);
    }

    protected int _delta;

    // from interface Streamable
    public void readObject (com.threerings.io.ObjectInputStream ins)
        throws java.io.IOException, java.lang.ClassNotFoundException
    {
        super.readObject(ins);
        com.threerings.io.GenStreamUtil.readField(com.threerings.stats.data.IntStatIncrementer.class, "_delta", this, ins);
    }

    // from interface Streamable
    public void writeObject (com.threerings.io.ObjectOutputStream out)
        throws java.io.IOException
    {
        super.writeObject(out);
        com.threerings.io.GenStreamUtil.writeField(com.threerings.stats.data.IntStatIncrementer.class, "_delta", this, out);
    }
}
