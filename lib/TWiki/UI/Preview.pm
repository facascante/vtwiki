# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 1999-2013 Peter Thoeny, peter[at]thoeny.org
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

package TWiki::UI::Preview;

use strict;
use Error qw( :try );

require TWiki;
require TWiki::UI::Save;
require TWiki::OopsException;

require Assert;

sub preview {
    my $session = shift;

    my $query = $session->{request};
    my $web = $session->{webName};
    my $topic = $session->{topicName};
    my $user = $session->{user};

    my( $meta, $text, $saveOpts, $merged ) =
      TWiki::UI::Save::buildNewTopic($session, 'preview');

    # Note: param(formtemplate) has already been decoded by buildNewTopic
    # so the $meta entry reflects if it was used.
    my $formFields = '';
    my $form = $meta->get('FORM') || '';
    if( $form ) {
        $form = $form->{name}; # used later on as well
        require TWiki::Form;
        my $formDef = new TWiki::Form( $session, $web, $form );
        unless( $formDef ) {
            throw TWiki::OopsException( 'attention',
                                        def => 'no_form_def',
                                        web => $session->{webName},
                                        topic => $session->{topicName},
                                        params => [ $web, $form ] );
        }
        $formFields = $formDef->renderHidden( $meta, 0 );
    }

    $session->{plugins}->dispatch(
        'afterEditHandler', $text, $topic, $web );

    my $skin = $session->getSkin();
    my $tmpl = $session->templates->readTemplate( 'preview', $skin );
    if( $saveOpts->{minor} ) {
        $tmpl =~ s/%DONTNOTIFYCHECKBOX%/checked="checked"/go;
    } else {
        $tmpl =~ s/%DONTNOTIFYCHECKBOX%//go;
    }
    if( $saveOpts->{forcenewrevision} ) {
        $tmpl =~ s/%FORCENEWREVISIONCHECKBOX%/checked="checked"/go;
    } else {
        $tmpl =~ s/%FORCENEWREVISIONCHECKBOX%//go;
    }
    my $saveCmd = $query->param( 'cmd' ) || '';
    $tmpl =~ s/%CMD%/$saveCmd/go;

    my $redirectTo = $query->param( 'redirectto' ) || '';
    $tmpl =~ s/%REDIRECTTO%/$redirectTo/go;

    my $metaPreferences = $query->param( 'metapreferences' ) || '';
    $metaPreferences = TWiki::entityEncode( $metaPreferences, "\n" );
    $tmpl =~ s/%METAPREFERENCES%/$metaPreferences/go;

    $tmpl =~ s/%FORMTEMPLATE%/$form/g;

    my $parent = $meta->get('TOPICPARENT');
    $parent = $parent->{name} if( $parent );
    $parent ||= '';
    $tmpl =~ s/%TOPICPARENT%/$parent/g;

    $session->enterContext( 'can_render_meta', $meta );

    my $dispText = $text;
    $dispText = $session->handleCommonTags( $dispText, $web, $topic, $meta );
    $dispText = $session->renderer->getRenderedVersion( $dispText, $web, $topic );

    # Disable links and inputs in the text
    $dispText =~ s#<a\s[^>]*>(.*?)</a>#<span class="twikiEmulatedLink">$1</span>#gis;
    $dispText =~ s/<(input|button|textarea) /<$1 disabled="disabled" /gis;
    $dispText =~ s(</?form(|\s.*?)>)()gis;
    $dispText =~ s/(<[^>]*\bon[A-Za-z]+=)('[^']*'|"[^"]*")/$1''/gis;

    $tmpl = $session->handleCommonTags( $tmpl, $web, $topic, $meta );
    $tmpl = $session->renderer->getRenderedVersion( $tmpl, $web, $topic );
    $tmpl =~ s/%TEXT%/$dispText/go;
    $tmpl =~ s/%FORMFIELDS%/$formFields/go;

    # SMELL: this should be done using CGI::hidden
    $text = TWiki::entityEncode( $text, "\n" );

    $tmpl =~ s/%HIDDENTEXT%/$text/go;

    $tmpl =~ s/<\/?(nop|noautolink)\/?>//gis;
    
    #I don't know _where_ these should be done, so I'll do them as late as possible
    my $originalrev = $query->param( 'originalrev' ); # rev edit started on
    #ASSERT($originalrev ne '%ORIGINALREV%') if DEBUG;
    $tmpl =~ s/%ORIGINALREV%/$originalrev/go;
    my $templatetopic = $query->param( 'templatetopic');
    #ASSERT($templatetopic ne '%TEMPLATETOPIC%') if DEBUG;
    $tmpl =~ s/%TEMPLATETOPIC%/$templatetopic/go;
    my $newtopic = $query->param( 'newtopic' );
    #ASSERT($newtopic ne '%NEWTOPIC%') if DEBUG;
    $tmpl =~ s/%NEWTOPIC%/$newtopic/go;


    $session->writeCompletePage( $tmpl );
}

1;
