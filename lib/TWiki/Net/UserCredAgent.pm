# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2007-2013 Peter Thoeny, peter[at]thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
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

# LWP::UserAgent subclass used to pass in username and password,
# and use the TWiki proxy setup

package TWiki::Net::UserCredAgent;
use base 'LWP::UserAgent';

sub new {
    my ($class, $user, $pass, $url) = @_;
    my $this = $class->SUPER::new();
    $this->{user} = $user;
    $this->{pass} = $pass;
    
    if (defined ($TWiki::cfg{PROXY}{SkipProxyForDomains})) {
        my @skipdomains =  split( /[\,\s]+/, $TWiki::cfg{PROXY}{SkipProxyForDomains});
        $this->no_proxy(@skipdomains);
     }

    if ($TWiki::cfg{PROXY}{HOST}) {
        my $proxyURL = $TWiki::cfg{PROXY}{HOST};
        $proxyURL = 'http://' . $proxyURL unless( $proxyURL =~ /^https?:\/\// ); 
        if ($TWiki::cfg{PROXY}{PORT}) {
            $proxyURL .= ':'.$TWiki::cfg{PROXY}{PORT};
        }
        $this->proxy([ 'http', 'https' ], $proxyURL);
    }
    return $this;
}

sub get_basic_credentials {
    my($this, $realm, $uri) = @_;
    return ($this->{user}, $this->{pass});
};

1;
