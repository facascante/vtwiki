# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2001-2013 Peter Thoeny, peter[at]thoeny.org
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
# See bottom of file for license and copyright details

# The bulk of this object is a parser for form definitions. All the
# intelligence is in the individual field types.

=pod

---+ package TWiki::Form

Object representing a single form definition.

Form definitions are mainly used to control rendering of a form for
editing, though there is some application login there that handles
transferring values between edits and saves.

A form definition consists of a TWiki::Form object, which has a list
of field definitions. Each field definition is an object of a type
derived from TWiki::Form::FieldDefinition. These objects are responsible
for the actual syntax and semantics of the field type. Form definitions
are parsed from TWiki tables, and the types are mapped by name to a
class declared in TWiki::Form::* - for example, the =text= type is mapped
to =TWiki::Form::Text= and the =checkbox= type to =TWiki::Form::Checkbox=.

The =TWiki::Form::FieldDefinition= class declares default behaviours for
types that accept a single value in their definitions. The
=TWiki::Form::ListFieldDefinition= extends this for types that have lists
of possible values.

=cut

package TWiki::Form;

use strict;
use Assert;
use Error qw( :try );

# The following are reserved as URL parameters to scripts and may not be
# used as field names in forms.
my %reservedFieldNames =
  map { $_ => 1 }
    ( 'action', 'breaklock', 'contenttype', 'cover', 'dontnotify', 'editaction',
      'forcenewrevision', 'formtemplate', 'onlynewtopic', 'onlywikiname',
      'originalrev', 'skin', 'templatetopic', 'text', 'topic', 'topicparent', 'user'
    );

=pod

---++ ClassMethod new ( $session, $web, $form, $def )

Looks up a form in the session object or, if it hasn't been read yet,
reads it frm the form definition topic on disc.
   * $web - default web to recover form from, if $form doesn't specify a web
   * =$form= - topic name to read form definition from
   * =$def= - optional. a reference to a list of field definitions. if present,
              these definitions will be used, rather than those in =$form=.

May throw TWiki::OopsException

=cut

sub new {
    my( $class, $session, $web, $form, $def ) = @_;

    ( $web, $form ) =
      $session->normalizeWebTopicName( $web, $form );

    my $this = $session->{forms}->{"$web.$form"};
    unless( $this ) {

        $this = bless(
            {
                session => $session,
                web => $web,
                topic => $form,
            }, $class );

        unless ( $def ) {

            my $store = $session->{store};

            # Read topic that defines the form
            unless( $store->topicExists( $web, $form ) ) {
                return undef;
            }
            # Item6398: Ignore view permission of form definition topic
            my( $meta, $text ) = $store->readTopic( undef, $web, $form, undef );

            $this->{fields} = _parseFormDefinition( $this, $meta, $text );

        } else {

            $this->{fields} = $def;

        }
        $session->{forms}->{"$web.$form"} = $this;
    }

    return $this;
}

=begin twiki

---++ ObjectMethod finish()
Break circular references.

=cut

# Note to developers; please undef *all* fields in the object explicitly,
# whether they are references or not. That way this method is "golden
# documentation" of the live fields in the object.
sub finish {
    my $this = shift;
    undef $this->{web};
    undef $this->{topic};
    foreach ( @{$this->{fields}} ) {
        $_->finish();
    }
    undef $this->{fields};
    undef $this->{session};
}

=pod

---++ StaticMethod fieldTitle2FieldName($title) -> $name
Chop out all except A-Za-z0-9_. from a field name to create a
valid "name" for storing in meta-data

=cut

sub fieldTitle2FieldName {
    my( $text ) = @_;
    return '' unless defined( $text );
    $text =~ s/<nop>//g; # support <nop> character in title
    $text =~ s/[^A-Za-z0-9_\.]//g;
    return $text;
}

# Get definition from supplied topic text
# Returns array of arrays
#   1st - list fields
#   2nd - name, title, type, size, vals, tooltip, attributes
#   Possible attributes are "M" (mandatory field)
sub _parseFormDefinition {
    my( $this, $meta, $text ) = @_;

    my $store = $this->{session}->{store};
    my @fields = ();
    my $inBlock = 0;
    $text =~ s/\r//g;
    $text =~ s/\\\n//g; # remove trailing '\' and join continuation lines

    # | *Name:* | *Type:* | *Size:* | *Value:*  | *Tooltip message:* | *Attributes:* |
    # Tooltip and attributes are optional
    foreach my $line ( split( /\n/, $text ) ) {
        if( $line =~ /^\s*\|.*Name[^|]*\|.*Type[^|]*\|.*Size[^|]*\|/ ) {
            $inBlock = 1;
            next;
        }
        # Only insist on first field being present FIXME - use oops page instead?
        if( $inBlock && $line =~ s/^\s*\|\s*// ) {
            $line =~ s/\\\|/\007/g; # protect \| from split
            my( $title, $type, $size, $vals, $tooltip, $attributes ) =
                map { s/\007/|/g; $_ }
                split( /\s*\|\s*/, $line );

            $title ||= '';

            $type ||= '';
            $type = lc $type;
            $type =~ s/^\s*//go;
            $type =~ s/\s*$//go;
            $type = 'text' if( ! $type );

            $size ||= '';
            $size = $this->{session}->handleCommonTags( $size, $this->{web}, $this->{topic}, $meta );
            $size =~ s/<\/?(nop|noautolink)\/?>//go;
            $size =~ s/^\s+//g;
            $size =~ s/\s+$//g;

            $vals ||= '';
            $vals = $this->{session}->handleCommonTags( $vals, $this->{web}, $this->{topic}, $meta );
            $vals =~ s/<\/?(nop|noautolink)\/?>//go;
            $vals =~ s/^\s+//g;
            $vals =~ s/\s+$//g;

            # SMELL: This expansion of $users is undocumented, AFAICT not
            # used, and downright *dangerous* (it won't work with a non-TWiki
            # user mapping for example) so in the interests of good hygiene,
            # I have removed it (CC, 30 Jun 07).
            #if( $vals eq '$users' ) {
            #    $vals = $TWiki::cfg{UsersWebName} . '.' .
            #      join( ", ${TWiki::cfg{UsersWebName}}.",
            #        ( $store->getTopicNames( $TWiki::cfg{UsersWebName} )));
            #}

            $tooltip ||= '';

            $attributes ||= '';
            $attributes =~ s/\s*//go;
            $attributes = '' if( ! $attributes );

            my $definingTopic = "";
            if( $title =~ /\[\[(.+)\]\[(.+)\]\]/ )  {
                # use common defining topics with different field titles
                $definingTopic = fieldTitle2FieldName( $1 );
                $title = $2;
            }

            my $name = fieldTitle2FieldName( $title );

            # Rename fields with reserved names
            if( $reservedFieldNames{$name} ) {
                $name .= '_';
            }

            my $fieldDef = $this->createField(
                  $type,
                  name => $name,
                  title => $title,
                  size => $size,
                  value => $vals,
                  tooltip => $tooltip,
                  attributes => $attributes,
                  definingTopic => $definingTopic,
                  web => $this->{web},
                  topic => $this->{topic}
                );
            push( @fields, $fieldDef );

            $this->{mandatoryFieldsPresent} ||= $fieldDef->isMandatory();
        } else {
            $inBlock = 0;
        }
    }

    return \@fields;
}

# PROTECTED
# Create a field object. Done like this so that this method can be
# overridden by subclasses to extend the range of field types.
sub createField {
    my $this = shift;
    my $type = shift;

    my $class = $type;
    $class =~ /^(\w*)/; # cut off +buttons etc

    # The following is a workaround for a bug in Perl 5.8.4 that was ultimately fixed on Perl 5.8.7-8
    # see http://bugs.debian.org/303308
    # using $class=TWiki::Sandbox::untaintUnchecked($class) also works but is one more method call.
    my $workaround=$1;
    $class = 'TWiki::Form::'.ucfirst( $workaround );

    eval 'require '.$class;
    if( $@ ) {
        # Type not available; use base type
        require TWiki::Form::FieldDefinition;
        $class = 'TWiki::Form::FieldDefinition';
    }
    return $class->new( session => $this->{session}, type => $type, @_ );
}

# Generate a link to the given topic, so we can bring up details in a
# separate window.
sub _link {
    my( $this, $meta, $string, $tooltip, $topic ) = @_;

    $string =~ s/[\[\]]//go;

    $topic ||= $string;
    my $defaultToolTip = $this->{session}->i18n->maketext( 'Details in separate window' );
    $tooltip ||= $defaultToolTip;

    my $web;
    ( $web, $topic ) = $this->{session}->normalizeWebTopicName( $this->{web}, $topic );

    my $link;

    my $store = $this->{session}->{store};
    if( $store->topicExists( $web, $topic ) ) {
        $link =
          CGI::a(
               { target => $topic,
                 onclick => 'return launchWindow( "'.$web.'","'.$topic.'" )',
                 title => $tooltip,
                 href =>$this->{session}->getScriptUrl( 0, 'view', $web, $topic ),
                 rel => 'nofollow'
               },
               $string
              );
    } else {
        my $expanded = $this->{session}->handleCommonTags( $string, $web, $topic, $meta );
        if ( $tooltip ne $defaultToolTip ) {
            $link = CGI::span ( { title => $tooltip }, $expanded );
        } else {
            $link = $expanded;
        }
    }

    return $link;
}

=pod

---++ ObjectMethod renderForEdit( $web, $topic, $meta ) -> $html

   * =$web= the web of the topic being rendered
   * =$topic= the topic being rendered
   * =$meta= the meta data for the form

Render the form fields for entry during an edit session, using data values
from $meta

=cut

sub renderForEdit {
    my( $this, $web, $topic, $meta ) = @_;
    ASSERT($meta->isa( 'TWiki::Meta')) if DEBUG;
    require CGI;
    my $session = $this->{session};

    if( $this->{mandatoryFieldsPresent} ) {
        $session->enterContext( 'mandatoryfields' );
    }
    my $tmpl = $session->templates->readTemplate( "form" );
    $tmpl = $session->handleCommonTags( $tmpl, $web, $topic, $meta );

    # Note: if WEBFORMS preference is not set, can only delete form.
    $tmpl =~ s/%FORMTITLE%/_link( $this, $meta, $this->{web}.'.'.$this->{topic} )/ge;
    my( $text, $repeatTitledText, $repeatUntitledText, $afterText ) = split( /%REPEAT%/, $tmpl );

    foreach my $fieldDef ( @{$this->{fields}} ) {

        my $value;
        my $tooltip = $fieldDef->{tooltip};
        my $definingTopic = $fieldDef->{definingTopic};
        my $title = $fieldDef->{title};
        my $tmp = '';
        if(! $title && !$fieldDef->isEditable() ) {
            # Special handling for untitled labels.
            # SMELL: Assumes that uneditable fields are not multi-valued
            $tmp = $repeatUntitledText;
            $value =
              $session->{renderer}->getRenderedVersion(
                  $session->handleCommonTags( $fieldDef->{value}, $web, $topic, $meta ) );
        } else {
            $tmp = $repeatTitledText;

            if( defined( $fieldDef->{name} )) {
                my $field = $meta->get( 'FIELD', $fieldDef->{name} );
                $value = $field->{value};
            }
            my $extra = ''; # extras on col 0

            unless( defined( $value )) {
                my $dv = $fieldDef->getDefaultValue( $value );
                if( defined( $dv )) {
                    $dv = $this->{session}->handleCommonTags( $dv, $web, $topic, $meta );
                    $value = TWiki::expandStandardEscapes( $dv ); # Item2837
                }
            }

            # Give plugin field types a chance first (but no chance to add to
            # col 0 :-(
            # SMELL: assumes that the field value is a string
            my $output = $session->{plugins}->dispatch(
                  'renderFormFieldForEditHandler',
                  $fieldDef->{name}, $fieldDef->{type},
                  $fieldDef->{size}, $value, $fieldDef->{attributes},
                  $fieldDef->{value}
                );

            if( $output ) {
                $value = $output;
            } else {
                ( $extra, $value ) = $fieldDef->renderForEdit( $web, $topic, $value );
            }

            if( $fieldDef->isMandatory() ) {
                $extra .= CGI::span( { class => 'twikiAlert' }, ' *' );
            }

            $tmp =~ s/%ROWTITLE%/_link( $this, $meta, $title, $tooltip, $definingTopic )/ge;
            $tmp =~ s/%ROWEXTRA%/$extra/g;
        }
        $tmp =~ s/%ROWVALUE%/$value/g;
        $text .= $tmp;
    }

    $text .= $afterText;
    return $text;
}

=pod

---++ ObjectMethod renderHidden( $meta ) -> $html

Render form fields found in the meta as hidden inputs, so they pass
through edits untouched.

=cut

sub renderHidden {
    my( $this, $meta ) = @_;
    ASSERT($meta->isa( 'TWiki::Meta')) if DEBUG;

    my $text = '';

    foreach my $field ( @{$this->{fields}} ) {
        $text .= $field->renderHidden( $meta );
    }

    return $text;
}

=pod

---++ ObjectMethod getFieldValuesFromQuery($query, $metaObject) -> ( $seen, \@missing )

Extract new values for form fields from a query.

   * =$query= - the query
   * =$metaObject= - the meta object that is storing the form values

For each field, if there is a value in the query, use it.
Otherwise if there is already entry for the field in the meta, keep it.

Returns the number of fields which had values provided by the query,
and a references to an array of the names of mandatory fields that were
missing from the query.

=cut

sub getFieldValuesFromQuery {
    my( $this, $query, $meta ) = @_;
    ASSERT($meta->isa( 'TWiki::Meta')) if DEBUG;
    my @missing;
    my $seen = 0;

    # Remove the old defs so we apply the
    # order in the form definition, and not the
    # order in the previous meta object. See Item1982.
    my @old = $meta->find( 'FIELD' );
    $meta->remove('FIELD');
    foreach my $fieldDef ( @{$this->{fields}} ) {
        my( $set, $present ) = $fieldDef->populateMetaFromQueryData( $query, $meta, \@old );
        if( $present ) {
            $seen++;
        }
        if( !$set && $fieldDef->isMandatory() ) {
            # Remember missing mandatory fields
            push( @missing, $fieldDef->{title} || "unnamed field" );
        }
    }
    return ( $seen, \@missing );
}

=pod

---++ ObjectMethod isTextMergeable( $name ) -> $boolean

   * =$name= - name of a form field (value of the =name= attribute)

Returns true if the type of the named field allows it to be text-merged.

If the form does not define the field, it is assumed to be mergeable.

=cut

sub isTextMergeable {
    my( $this, $name ) = @_;

    my $fieldDef = $this->getField( $name );
    if( $fieldDef ) {
        return $fieldDef->isTextMergeable();
    }
    # Field not found - assume it is mergeable
    return 1;
}

=pod

---++ ObjectMethod getField( $name ) -> $fieldDefinition

   * =$name= - name of a form field (value of the =name= attribute)

Returns a =TWiki::Form::FieldDefinition=, or undef if the form does not
define the field.

=cut

sub getField {
    my( $this, $name ) = @_;
    foreach my $fieldDef ( @{$this->{fields}} ) {
        return $fieldDef if ( $fieldDef->{name} && $fieldDef->{name} eq $name );
    }
    return undef;
}

=pod

---++ ObjectMethod getFields() -> \@fields

Return a list containing references to field name/value pairs.
Each entry in the list has a {name} field and a {value} field. It may
have other fields as well, which caller should ignore. The
returned list should be treated as *read only* (must not be written to).

=cut

sub getFields {
    my $this = shift;
    return $this->{fields};
}

sub renderForDisplay {
    my( $this, $meta ) = @_;

    my $templates = $this->{session}->templates;
    $templates->readTemplate( 'formtables' );

    my $text = $templates->expandTemplate( 'FORM:display:header' );

    my $rowTemplate = $templates->expandTemplate( 'FORM:display:row' );
    foreach my $fieldDef ( @{$this->{fields}} ) {
        my $fm = $meta->get( 'FIELD', $fieldDef->{name} );
        next unless $fm;
        my $fa = $fm->{attributes} || '';
        unless ( $fa =~ /H/ ) {
            my $row = $rowTemplate;
             # Legacy; was %A_TITLE% before it was $title
            $row =~ s/%A_TITLE%/\$title/g;
            $row =~ s/%A_VALUE%/\$value/g; # Legacy
            $text .= $fieldDef->renderForDisplay( $row, $fm->{value} );
        }
    }
    $text .= $templates->expandTemplate( 'FORM:display:footer' );
    $text =~ s/%A_TITLE%/$this->{web}.$this->{topic}][$this->{topic}/g;
    return $text;
}

1;
