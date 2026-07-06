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

package com.threerings.parlor.data;

import com.threerings.util.ActionScript;

/**
 * Models a parameter that can contain an integer value in a specified range.
 */
public class RangeParameter extends Parameter
{
    /** The minimum value of this parameter. */
    public int minimum;

    /** The maximum value of this parameter. */
    public int maximum;

    /** The starting value for this parameter. */
    public int start;

    @Override @ActionScript(omit=true)
    public String getLabel ()
    {
        return "m.range_" + ident;
    }

    @Override
    public Object getDefaultValue ()
    {
        return start;
    }

    // from interface Streamable
    public void readObject (com.threerings.io.ObjectInputStream ins)
        throws java.io.IOException, java.lang.ClassNotFoundException
    {
        com.threerings.io.GenStreamUtil.readField(com.threerings.parlor.data.Parameter.class, "ident", this, ins);
        com.threerings.io.GenStreamUtil.readField(com.threerings.parlor.data.Parameter.class, "name", this, ins);
        com.threerings.io.GenStreamUtil.readField(com.threerings.parlor.data.Parameter.class, "tip", this, ins);
        com.threerings.io.GenStreamUtil.readField(com.threerings.parlor.data.RangeParameter.class, "minimum", this, ins);
        com.threerings.io.GenStreamUtil.readField(com.threerings.parlor.data.RangeParameter.class, "maximum", this, ins);
        com.threerings.io.GenStreamUtil.readField(com.threerings.parlor.data.RangeParameter.class, "start", this, ins);
    }

    // from interface Streamable
    public void writeObject (com.threerings.io.ObjectOutputStream out)
        throws java.io.IOException
    {
        com.threerings.io.GenStreamUtil.writeField(com.threerings.parlor.data.Parameter.class, "ident", this, out);
        com.threerings.io.GenStreamUtil.writeField(com.threerings.parlor.data.Parameter.class, "name", this, out);
        com.threerings.io.GenStreamUtil.writeField(com.threerings.parlor.data.Parameter.class, "tip", this, out);
        com.threerings.io.GenStreamUtil.writeField(com.threerings.parlor.data.RangeParameter.class, "minimum", this, out);
        com.threerings.io.GenStreamUtil.writeField(com.threerings.parlor.data.RangeParameter.class, "maximum", this, out);
        com.threerings.io.GenStreamUtil.writeField(com.threerings.parlor.data.RangeParameter.class, "start", this, out);
    }
}
