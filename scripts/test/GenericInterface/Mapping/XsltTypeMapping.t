# --
# CareOnCloud ESM is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2019-2026 Rother OSS GmbH, https://otobo.io/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

use v5.24;
use strict;
use warnings;
use utf8;

# core modules

# CPAN modules
use Test2::V0;

# CareOnCloud ESM modules
use Kernel::System::UnitTest::RegisterOM;    # set up $Kernel::OM
use Kernel::GenericInterface::Mapping::XSLT;
use Kernel::GenericInterface::Debugger;

# Input as would be produced from an XSLT mapping that uses
# careoncloudType="..." attributes in the generated XML.

my $RawInput = {
    'ArticleID' => '2',
    'Event'     => 'ArticleEdit',
    'TicketID'  => '1',
};

my $InputWithTypeHints = {
    'ArticleID' => {
        'content'      => '2',
        'careoncloudXslType' => 'int'
    },
    'Event' => {
        'content'      => 'ArticleEdit',
        'careoncloudXslType' => 'array'
    },
    'Test' => {
        'Item' => {
            'content'      => '3.2',
            'careoncloudXslType' => 'float'
        },
        'Array' => [
            {
                'Item' => {
                    'content'      => '0',
                    'careoncloudXslType' => 'bool'
                }
            },
            {
                'Item' => {
                    'content'      => '1',
                    'careoncloudXslType' => 'bool'
                }
            },
            {
                'Item' => {
                    'content'      => 'false',
                    'careoncloudXslType' => 'bool'
                }
            }
        ],
        'Sub' => {
            'content'      => '1',
            'careoncloudXslType' => 'array'
        },
        'Thing' => [
            {
                'content'      => '1',
                'careoncloudXslType' => 'array int'
            },
            {
                'content'      => '2',
                'careoncloudXslType' => 'array int'
            },
            {
                'content'      => '3',
                'careoncloudXslType' => 'array int'
            }
        ]
    },
    'TicketID' => {
        'content'      => '1',
        'careoncloudXslType' => 'bool'
    }
};

# resulting Perl data structure after typehint reduction

my $Expected = {
    'ArticleID' => 2,
    'Event'     => [
        'ArticleEdit'
    ],
    'Test' => {
        'Item'  => '3.2',
        'Array' => [
            {
                'Item' => bless( do { \( my $o = 0 ) }, 'JSON::PP::Boolean' )
            },
            {
                'Item' => bless( do { \( my $o = 1 ) }, 'JSON::PP::Boolean' )
            },
            {
                'Item' => bless( do { \( my $o = 0 ) }, 'JSON::PP::Boolean' )
            }
        ],
        'Sub' => [
            '1'
        ],
        'Thing' => [
            1,
            2,
            3
        ]
    },
    'TicketID' => bless( do { \( my $o = 1 ) }, 'JSON::PP::Boolean' )
};

# MappingConf

my $MappingConfig = {
    'Config' => {
        'DataInclude'               => [],
        'EnableExtendedXSLTMapping' => 1,
        'PostRegExFilter'           => undef,
        'PostRegExValueCounter'     => undef,
        'PreRegExFilter'            => undef,
        'PreRegExValueCounter'      => undef,
        'Template'                  => '<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output omit-xml-declaration="yes" indent="yes"/>
  <xsl:strip-space elements="*"/>
  <xsl:template match="/">
    <RootElement>
      <TicketID careoncloudXslType="bool"><xsl:value-of select="/RootElement/TicketID" /></TicketID>
      <ArticleID careoncloudXslType="int"><xsl:value-of select="/RootElement/ArticleID" /></ArticleID>
      <Event careoncloudXslType="array"><xsl:value-of select="/RootElement/Event" /></Event>
      <Test>
        <Sub careoncloudXslType="array">1</Sub>
        <Item careoncloudXslType="float">3.2</Item>
        <Thing careoncloudXslType="array int">1</Thing>
        <Thing careoncloudXslType="array int">2</Thing>
        <Thing careoncloudXslType="array int">3</Thing>
        <Array><Item careoncloudXslType="bool">0</Item></Array>
        <Array><Item careoncloudXslType="bool">1</Item></Array>
        <Array><Item careoncloudXslType="bool">false</Item></Array>
      </Test>
      <xsl:copy-of select="/RootElement/OldTicketData"/>
    </RootElement>
  </xsl:template>
  </xsl:stylesheet>'
    },
    'Type' => 'XSLT'
};

# Test 1 - just the _ReduceTypedTreeData function in isolation

isnt( $InputWithTypeHints, $Expected );

my $Transformed = Kernel::GenericInterface::Mapping::XSLT->_ReduceTypedTreeData( Data => $InputWithTypeHints );

is( $Transformed, $Expected );

# Test 2 - use mapping

isnt( $RawInput, $Expected );

my $DebuggerObject = Kernel::GenericInterface::Debugger->new(
    DebuggerConfig => {
        DebugThreshold => 'error',
        TestMode       => 1,
    },
    WebserviceID      => 1,
    CommunicationType => 'Requester',
);

my $Mapping = Kernel::GenericInterface::Mapping::XSLT->new(
    MappingConfig  => $MappingConfig,
    DebuggerObject => $DebuggerObject,
);

$Transformed = $Mapping->Map( Data => $RawInput );

is( $Transformed->{Data}, $Expected );

done_testing;
