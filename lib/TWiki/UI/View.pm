# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 1999-2013 Peter Thoeny, peter[at]thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# Additional copyrights apply to some or all of the code in this
# file as follows:
# Based on parts of Ward Cunninghams original Wiki and JosWiki.
# Copyright (C) 1998 Markus Peter - SPiN GmbH (warpi@spin.de)
# Some changes by Dave Harris (drh@bhresearch.co.uk) incorporated
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

=pod

---+ package TWiki::UI::View

UI delegate for view function

=cut

package TWiki::UI::View;

use strict;
use integer;
use Monitor;

require TWiki;
require TWiki::UI;
require TWiki::Sandbox;
require TWiki::OopsException;

=pod

---++ StaticMethod view( $session )

=view= command handler.
This method is designed to be
invoked via the =UI::run= method.

Generate a complete HTML page that represents the viewed topics.
The view is controlled by CGI parameters as follows:

| =rev= | topic revision to view |
| =section= | restrict view to a named section |
| =raw= | no format body text if set |
| =skin= | comma-separated list of skin(s) to use |
| =contenttype= | Allows you to specify an alternate content type |

=cut

sub view {
    my $session = shift;

    my $query = $session->{request};
    my $webName = $session->{webName};
    my $topicName = $session->{topicName};

    my $raw = $query->param( 'raw' ) || '';
    my $contentType = $query->param( 'contenttype' );

    my $showRev = 1;
    my $logEntry = '';
    my $revdate = '';
    my $revuser = '';
    my $store = $session->{store};
    # is this view indexable by search engines? Default yes.
    my $indexableView = 1;

    TWiki::UI::checkWebExists( $session, $webName, $topicName, 'view' );

    my $skin = $session->getSkin();

    my $rev = $store->cleanUpRevID( $query->param( 'rev' ));

    my $topicExists =
      $store->topicExists( $webName, $topicName );

    # text and meta of the _latest_ rev of the topic
    my( $currText, $currMeta );
    # text and meta of the chosen rev of the topic
    my( $meta, $text );
    if( $topicExists ) {
        require TWiki::Time;
        ( $currMeta, $currText ) = $store->readTopic
          ( $session->{user}, $webName, $topicName, undef );
        TWiki::UI::checkAccess( $session, $webName, $topicName,
                                'VIEW', $session->{user}, $currText );
        ( $revdate, $revuser, $showRev ) = $currMeta->getRevisionInfo();
        $revdate = TWiki::Time::formatTime( $revdate );

        if ( !$rev || $rev > $showRev ) {
            $rev = $showRev;
        }

        if( $rev < $showRev ) {
            ( $meta, $text ) = $store->readTopic
              ( $session->{user}, $webName, $topicName, $rev );

            ( $revdate, $revuser ) = $meta->getRevisionInfo();
            $revdate = TWiki::Time::formatTime( $revdate );
            $logEntry .= 'r'.$rev;
        } else {
            # viewing the most recent rev
            ( $text, $meta ) = ( $currText, $currMeta );
        }

        # So we're reading an existing topic here.  It is about time
        # to apply the 'section' selection (and maybe others in the
        # future as well).  $text is cleared unless a named section
        # matching the 'section' URL parameter is found.
        if (my $section  =  $query->param('section')) {
            my ( $ntext, $sections ) = TWiki::parseSections( $text );
            $text = ''; # in the beginning, there was ... NO section
          FINDSECTION:
            for my $s (@$sections) {
                if ($s->{type} eq 'section'  &&  $s->{name} eq $section) {
                    $text = substr( $ntext, $s->{start}, $s->{end}-$s->{start} );
                    last FINDSECTION;
                }
            }
        }

    } else { # Topic does not exist yet

        if( $query->param( 'createifnotexist' ) ) {
            # redirect to the save script to force topic creation
            my $redirecturl = $session->getScriptUrl( 1, 'save', $webName, $topicName );

            # force POST method because GET is disabled in save
            $query->request_method( 'POST' ); # SMELL: Security issue?
            $query->delete( 'createifnotexist' ); # remove 'createifnotexist' parameter

            # add crypt token if needed
            if( $TWiki::cfg{CryptToken}{Enable} ) {
                $query->param( 'crypttoken', $session->CRYPTTOKEN() );
            }

            # redirect to save script, all URL parameters are taken into account
            $session->redirect( $redirecturl, 1 );
        }

        $indexableView = 0;
        $session->enterContext( 'new_topic' );
        $rev = 1;
        if( TWiki::isValidTopicName( $topicName )) {
            ( $currMeta, $currText ) =
              TWiki::UI::readTemplateTopic( $session, 'WebTopicViewTemplate' );
        } else {
            ( $currMeta, $currText ) =
              TWiki::UI::readTemplateTopic( $session, 'WebTopicNonWikiTemplate' );
        }
        ( $text, $meta ) = ( $currText, $currMeta );
        $logEntry .= ' ' if( $logEntry );
        $logEntry .= '(not exist)';
    }

    if( $raw ) {
        $indexableView = 0;
        $logEntry .= ' ' if( $logEntry );
        $logEntry .= 'raw='.$raw;
        if( $raw eq 'debug' || $raw eq 'all' ) {
            $text = $store->getDebugText( $meta, $text );
        }
    }

    if( $query->param( 'extralog' ) ) {
        my $extraLog = $query->param( 'extralog' );
        $extraLog =~ s/`\|\x00-\x1f]//go; # Sanitize parameter value
        $logEntry .= ' ' if( $logEntry );
        $logEntry .= $extraLog;
    }

    if( $TWiki::cfg{Log}{view} ) {
        $session->writeLog( 'view', $webName.'.'.$topicName, $logEntry );
    }

    my( $mirrorSiteName, $mirrorViewURL, $mirrorLink, $mirrorNote ) =
      $session->readOnlyMirrorWeb( $webName );

    # Note; must enter all contexts before the template is read, as
    # TMPL:P is expanded on the fly in the template reader. :-(
    my( $revTitle, $revArg ) = ( '', '' );
    if( $mirrorSiteName ) {
        $session->enterContext( 'inactive' );
        unless( $topicExists ) {
            $text = '';
        }
    } elsif( $rev < $showRev ) {
        $session->enterContext( 'inactive' );
        # disable edit of previous revisions
        $revTitle = '(r'.$rev.')';
        $revArg = '&rev='.$rev;
    }

    my $template = $query->param( 'template' ) ||
      $session->{prefs}->getPreferencesValue( 'VIEW_TEMPLATE' ) ||
        'view';

    # Always use default view template for raw=debug, raw=all and raw=on
    if( $raw =~ /^(debug|all|on)$/ ) {
        $template = 'view';
    }

    my $tmpl = $session->templates->readTemplate( $template, $skin );
    if( !$tmpl && $template ne 'view' ) {
        $tmpl = $session->templates->readTemplate( 'view', $skin );
    }

    if( !$tmpl ) {
        throw TWiki::OopsException( 'attention',
                                    def => 'no_such_template',
                                    web => $webName,
                                    topic => $topicName,
                                    params => [ $template, 'VIEW_TEMPLATE' ] );
    }

    $tmpl =~ s/%REVINFO%/%REVINFO%$mirrorNote/go;
    $tmpl =~ s/%REVTITLE%/$revTitle/g;
    $tmpl =~ s/%REVARG%/$revArg/g;

    if( $indexableView &&
          $TWiki::cfg{AntiSpam}{RobotsAreWelcome} &&
            !$query->param() ) {
        # it's an indexable view type, there are no parameters
        # on the url, and robots are welcome. Remove the NOINDEX meta tag
        $tmpl =~ s/<meta name="robots"[^>]*>//goi;
    }

    # Show revisions around the one being displayed
    # we start at $showRev then possibly jump near $rev if too distant
    my $revsToShow = $TWiki::cfg{NumberOfRevisions} + 1;
    $revsToShow = $showRev if $showRev < $revsToShow;
    my $doingRev = $showRev;
    my $revs = '';
    while( $revsToShow > 0 ) {
        $revsToShow--;
        if( $doingRev == $rev) {
            $revs .= 'r'.$rev;
        } else {
            $revs .= CGI::a({
                             href=>$session->getScriptUrl( 0,
                                                           'view',
                                                           $webName,
                                                           $topicName,
                                                           rev => $doingRev ),
                             rel => 'nofollow'
                            },
                            "r$doingRev" );
        }
        if ( $doingRev - $rev >= $TWiki::cfg{NumberOfRevisions} ) {
            # we started too far away, need to jump closer to $rev
            use integer;
            $doingRev = $rev + $revsToShow / 2;
            $doingRev = $revsToShow if $revsToShow > $doingRev;
            $revs .= ' | ';
            next;
        }
        if( $revsToShow ) {
            $revs .= '&nbsp;' . CGI::a
              ( { href=>$session->getScriptUrl(
                  0, 'rdiff', $webName, $topicName,
                  rev1 => $doingRev,
                  rev2 => $doingRev-1 ),
                  rel => 'nofollow' },
                '&lt;' ) . '&nbsp;';
        }
        $doingRev--;
    }

    $tmpl =~ s/%REVISIONS%/$revs/go;

    ## SMELL: This is also used in TWiki::_TOC. Could insert a tag in
    ## TOC and remove all those here, finding the parameters only once
    my @qparams = ();
    foreach my $name ( $query->param ) {
      next if ($name eq 'keywords');
      next if ($name eq 'topic');
      push @qparams, $name => $query->param($name);
    }
    $tmpl =~ s/%QUERYPARAMSTRING%/TWiki::_make_params(1,@qparams)/geo;

    # extract header and footer from the template, if there is a
    # %TEXT% tag marking the split point. The topic text is inserted
    # in place of the %TEXT% tag. The text before this tag is inserted
    # as header, the text after is inserted as footer. If there is a
    # %STARTTEXT% tag present, the header text between %STARTTEXT% and
    # %TEXT is rendered together, as is the footer text between %TEXT%
    # and %ENDTEXT%, if present. This allows correct handling of TWiki
    # markup in header or footer if those do require examination of the
    # topic text to work correctly (e.g., %TOC%).
    # Note: This feature is experimental and may be replaced by an
    # alternative solution not requiring additional tags.
    my( $start, $end );
    if( $tmpl =~ m/^(.*)%TEXT%(.*)$/s ) {
        my @starts = split( /%STARTTEXT%/, $1 );
        if ( $#starts > 0 ) {
            # we know that there is something before %STARTTEXT%
            $start = $starts[0];
            $text = $starts[1] . $text;
        } else {
            $start = $1;
        }
        my @ends = split( /%ENDTEXT%/, $2 );
        if ( $#ends > 0 ) {
            # we know that there is something after %ENDTEXT%
            $text .= $ends[0];
            $end = $ends[1];
        } else {
            $end = $2;
        }
    } else {
        my @starts = split( /%STARTTEXT%/, $tmpl );
        if ( $#starts > 0 ) {
            # we know that there is something before %STARTTEXT%
            $start = $starts[0];
            $text = $starts[1];
        } else {
            $start = $tmpl;
            $text = '';
        }
        $end = '';
    }

    # If minimalist is set, images and anchors will be stripped from text
    my $minimalist = 0;
    if( $contentType ) {
        $minimalist = ( $skin =~ /\brss/ );
    } elsif( $skin =~ /\brss/ ) {
        $contentType = 'text/xml';
        $minimalist = 1;
    } elsif( $skin =~ /\bxml/ ) {
        $contentType = 'text/xml';
        $minimalist = 1;
    } elsif( $raw eq 'text' || $raw eq 'all' ) {
        $contentType = 'text/plain';
    } else {
        $contentType = 'text/html'
    }
    $session->{SESSION_TAGS}{MAXREV} = $showRev;
    $session->{SESSION_TAGS}{CURRREV} = $rev;

    # Set page generation mode to RSS if using an RSS skin
    $session->enterContext( 'rss' ) if $skin =~ /\brss/;

    # Set the meta-object that contains the rendering info
    # SMELL: hack to get around not having a proper topic object model
    $session->enterContext( 'can_render_meta', $meta );

    my $page;
    # Legacy: If the _only_ skin is 'text' it is used like this:
    # http://.../view/Codev/MyTopic?skin=text&contenttype=text/plain&raw=on
    # which shows the topic as plain text; useful for those who want
    # to download plain text for the topic. So when the skin is 'text'
    # we do _not_ want to create a textarea.
    # raw=on&skin=text is deprecated; use raw=text instead.
    Monitor::MARK('Ready to render');
    if( $raw eq 'text' || $raw eq 'all' || ( $raw && $skin eq 'text' )) {
        # use raw text
        $page = $text;
    } else {
        my @args = ( $session, $webName, $topicName, $meta, $minimalist );

        $session->enterContext( 'header_text' );
        $page = _prepare($start, @args);
        $session->leaveContext( 'header_text' );
        Monitor::MARK('Rendered header');

        if( $raw ) {
            if ($text) {
                my $p = $session->{prefs};
                $page .=
                  CGI::textarea(
                      -readonly => 'readonly',
                      -rows => $p->getPreferencesValue('EDITBOXHEIGHT'),
                      -cols => $p->getPreferencesValue('EDITBOXWIDTH'),
                      -style => $p->getPreferencesValue('EDITBOXSTYLE'),
                      -class => 'twikiTextarea twikiTextareaRawView',
                      -id => 'topic',
                      -default => $text
                     );
            }
        } else {
            $session->enterContext( 'body_text' );
            $page .= _prepare($text, @args);
            $session->leaveContext( 'body_text' );
        }

        Monitor::MARK('Rendered body');
        $session->enterContext( 'footer_text' );
        $page .= _prepare($end, @args);
        $session->leaveContext( 'footer_text' );
        Monitor::MARK('Rendered footer');
    }
    # Output has to be done in one go, because if we generate the header and
    # then redirect because of some later constraint, some browsers fall over
    $session->writeCompletePage( $page, 'view', $contentType );
    Monitor::MARK('Wrote HTML');
}

sub _prepare {
    my( $text, $session, $webName, $topicName, $meta, $minimalist) = @_;

    $text = $session->handleCommonTags( $text, $webName, $topicName, $meta );
    $text = $session->renderer->getRenderedVersion( $text, $webName, $topicName );
    $text =~ s/( ?) *<\/?(nop|noautolink)\/?>\n?/$1/gois;

    if( $minimalist ) {
        $text =~ s/<img [^>]*>//gi;  # remove image tags
        $text =~ s/<a [^>]*>//gi;    # remove anchor tags
        $text =~ s/<\/a>//gi;        # remove anchor tags
    }

    return $text;
}

=pod

---++ StaticMethod viewfile( $session, $web, $topic, $query )

=viewfile= command handler.
This method is designed to be
invoked via the =UI::run= method.
Command handler for viewfile. View a file in the browser.
Some parameters are passed in CGI query:
| =filename= | Attachment to view |
| =rev= | Revision to view |

=cut

sub viewfile {
    my $session = shift;

    my $query = $session->{request};

    my $topic = $session->{topicName};
    my $webName = $session->{webName};

    my @path = split( '/', $query->path_info() );
    shift( @path )unless $path[0];
    my $fileName;
    if( defined( $query->param( 'filename' ))) {
        $fileName = $query->param( 'filename' );
    } else {

         # Ok file name is not comming from explicit query parameter
         # Let us cook from @path

         $fileName = pop( @path );

         #Let us redefine web/topic - fix of Item5967

        if( $fileName =~ /\.([^.]+)$/ ) {  #file has extension
            my $suffix = $1;
            my $presuffix = $fileName;
            $presuffix  =~ s/\.$suffix$//;
            $webName =~ s/$presuffix$//o;  #let us drop filename part from webName
            $webName =~ s/\/$//o;
            if ($webName =~ /\/([^\/]+)$/) {$topic = $1;} #topic name defined here
            $webName =~ s/$topic$//o;
            $webName =~ s/\/$//o;

         } else {    #file does not have extension
            $webName =~ s/$fileName$//o;  #let us drop the filename from webName
            $webName =~ s/\/$//o;
            if ($webName =~ /\/([^\/]+)$/) {$topic = $1;}  #topic name redefined here
            $webName =~ s/$topic$//o;
            $webName =~ s/\/$//o;
        }
    }


    if (!$fileName) {
        throw TWiki::OopsException( 'attention',
                                    def => 'no_such_attachment',
                                    web => 'Unknown',
                                    topic => 'Unknown',
                                    params => [ 'viewfile', '?' ] );
    }

    $fileName = TWiki::Sandbox::sanitizeAttachmentName( $fileName );

    my $rev = $session->{store}->cleanUpRevID( $query->param( 'rev' ) );
    unless( $fileName && $session->{store}->attachmentExists(
        $webName, $topic, $fileName )) {
        throw TWiki::OopsException( 'attention',
                                    def => 'no_such_attachment',
                                    web => $webName,
                                    topic => $topic,
                                    params => [ 'viewfile', $fileName||'?' ] );
    }

    my $logEntry = $fileName;
    if( $rev ) {
        $logEntry .= ", r$rev";
    }
    if( $TWiki::cfg{Log}{viewfile} ) {
        $session->writeLog( 'viewfile', $webName.'.'.$topic, $logEntry );
    }


# TSA SMELL: Maybe could be less memory hungry if get a file handle
# and set response body to it. This way engines could send data the
# best way possible to each one
    my $fileContent = $session->{store}->readAttachment(
        $session->{user}, $webName, $topic, $fileName, $rev );

    my $type = _suffixToMimeType( $session, $fileName );
    my $length =  length( $fileContent );
    my $dispo = 'inline;filename='.$fileName;

    $session->{response}->header(-type => $type, qq(Content-Disposition="$dispo") );
    $session->{response}->body($fileContent);
}

sub _suffixToMimeType {
    my( $session, $theFilename ) = @_;

    my $mimeType = 'text/plain';
    if( $theFilename =~ /\.([^.]+)$/ ) {
        my $suffix = $1;
        my @types = grep{ s/^\s*([^\s]+).*?\s$suffix\s.*$/$1/i }
          map{ $_.' ' }
            split( /[\n\r]/,
                   TWiki::readFile( $TWiki::cfg{MimeTypesFileName} ) );
        $mimeType = $types[0] if( @types );
    }
    return $mimeType;
}

1;
