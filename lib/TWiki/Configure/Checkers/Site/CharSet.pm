# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2000-2013 Peter Thoeny, peter[at]thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# Additional copyrights apply to some or all of the code in this
# file as follows:
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# As per the GPL, removal of this notice is prohibited.

package TWiki::Configure::Checkers::Site::CharSet;
use base 'TWiki::Configure::Checker';

use strict;

sub check {
    my $this = shift;

    # Extract the character set from locale and use in HTML templates
    # and HTTP headers
    unless( defined $TWiki::cfg{Site}{CharSet} ) {
        $TWiki::cfg{Site}{Locale} =~ m/\.([a-z0-9_-]+)$/i;
        $TWiki::cfg{Site}{CharSet} = $1 if defined $1;
        $TWiki::cfg{Site}{CharSet} =~ s/^utf8$/utf-8/i;
        $TWiki::cfg{Site}{CharSet} =~ s/^eucjp$/euc-jp/i;
        $TWiki::cfg{Site}{CharSet} = lc $TWiki::cfg{Site}{CharSet};
    }
    return '';
}

1;
