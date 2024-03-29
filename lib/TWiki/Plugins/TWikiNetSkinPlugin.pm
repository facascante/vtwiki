# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (c) 2007-2011 TWiki Inc. All Rights Reserved.
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
# For licensing info read LICENSE file in the TWiki root.

package TWiki::Plugins::TWikiNetSkinPlugin;

use strict;

our $VERSION = '$Rev: 21647 (2013-02-16) $';
our $RELEASE = '2011-07-10';

our $SHORTDESCRIPTION = 'Helps formatting TWikiNetSkin design. Enable by setting the skin to "twikinet"';

# Name of this Plugin, only used in this module
my $pluginName = 'TWikiNetSkinPlugin';
my $debug;

sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $TWiki::Plugins::VERSION < 1.026 ) {
        TWiki::Func::writeWarning(
            "Version mismatch between $pluginName and Plugins.pm");
        return 0;
    }

    $debug = $TWiki::cfg{Plugins}{TWikiNetSkinPlugin}{Debug} || 0;

    # check if the skin is currently set to TWikiNetSkin
    if ( !( TWiki::Func::getSkin() =~ /\btwikinet\b/ ) ) {
        return 0;
    }
    if ( !_isAllowed() ) {
        return 0;
    }

    # Plugin correctly initialized
    return 1;
}

sub _isAllowed {

   my $query = TWiki::Func::getCgiQuery();

   # disable with edittable edit
   my $editTable = $query->param("ettablenr");
   if (defined $editTable && $editTable ne '') {
       return 0;
   }
   return 1;
}

sub preRenderingHandler {

    # do not uncomment, use $_[0], $_[1]... instead

    my $insideBLOCKQUOTE = 0;
    my $insideTABLE      = 0;
     
    my @lines = split( /\r?\n/, $_[0] );
    for (@lines) {

        # change state:
        m|<blockquote>|i  && ( $insideBLOCKQUOTE = 1 );
        m|</blockquote>|i && ( $insideBLOCKQUOTE = 0 );

        if ( !$insideBLOCKQUOTE ) {
			
            if (/^\s*\|.*\|\s*$/) {

                # inside | table |
                if ( !$insideTABLE ) {
                    $insideTABLE = 1;
                    _prependTable($_);
                }
            }
            else {

                # outside | table |
                if ($insideTABLE) {
                    $insideTABLE = 0;
                    _appendTable($_);
                }
            }

        }
    }    #foreach
    $_[0] = join( "\n", @lines );
}

sub _prependTable {

    # do not uncomment, use $_[0] ... instead

    my $tableStart = <<'ENDTOP';
<table cellspacing="0" cellpadding="0" border="0" class="twikinetWrapperTable" rules="none">
<tr class="twikinetWrapperTableRow">
<td class="twikinetWrapperTableT twikinetWrapperTableTL"></td>
<td class="twikinetWrapperTableT twikinetWrapperTableTR"></td>
</tr>
<tr class="twikinetWrapperTableRow">
<td colspan="2" class="twikinetWrapperTableMain">
ENDTOP
    $_[0] = $tableStart . $_[0];
}

sub _appendTable {

    # do not uncomment, use $_[0] ... instead

    my $tableEnd = <<'ENDBOTTOM';
</td>
</tr>
<tr class="twikinetWrapperTableRow">
<td class="twikinetWrapperTableB twikinetWrapperTableBL"></td>
<td class="twikinetWrapperTableB twikinetWrapperTableBR"></td>
</tr>
</table>
ENDBOTTOM
    $_[0] = $tableEnd . $_[0];
}

sub postRenderingHandler {

    # do not uncomment, use $_[0], $_[1]... instead

    # '<h6>...</h6>' HTML rule
    my $regex = "<nop>$TWiki::regex{headerPatternHt}";
    $_[0] =~ s/(<h([2])>)(.*?)(<\/h\2>)/_formatHeader($1,$2,$3,$4)/geo;
}

=pod

Formats h2 headers

=cut

sub _formatHeader {
    my ( $startTag, $level, $contents, $endTag ) = @_;

    $startTag = '<h2 class="twikinetRoundedAttachments">';
    return $startTag
      . '<span class="twikinetHeader">'
      . $contents
      . '</span>'
      . $endTag;
}

1;
