=head1 NAME

 iMSCP::Modules::IpAddr - i-MSCP IpAddr module

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2018 by Laurent Declercq <l.declercq@nuxwin.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

package iMSCP::Modules::IpAddr;

use strict;
use warnings;
use Carp qw/ croak /;
use iMSCP::Debug qw/ error getLastError warning /;
use parent 'iMSCP::Modules::Abstract';

=head1 DESCRIPTION

 Module for processing of IP address entities

=head1 PUBLIC METHODS

=over 4

=item getEntityType( )

 Get entity type

 Return string entity type

=cut

sub getEntityType
{
    'IpAddr';
}

=item process( $ipId )

 Process module

 Param string $ipId Server IP unique identifier
 Return int 0 on success, other on failure

=cut

sub process
{
    my ($self, $ipId) = @_;

    my $rs = $self->_loadData( $ipId );
    return $rs if $rs;

    my @sql;
    if ( $self->{'_data'}->{'ip_status'} =~ /^to(?:add|change)$/ ) {
        $rs = $self->add();
        @sql = ( 'UPDATE server_ips SET ip_status = ? WHERE ip_id = ?', undef, ( $rs ? getLastError( 'error' ) || 'Unknown error' : 'ok' ), $ipId );
    } elsif ( $self->{'_data'}->{'ip_status'} eq 'todelete' ) {
        $rs = $self->delete();
        @sql = $rs
            ? ( 'UPDATE server_ips SET ip_status = ? WHERE ip_id = ?', undef, getLastError( 'error' ) || 'Unknown error', $ipId )
            : ( 'DELETE FROM server_ips WHERE ip_id = ?', undef, $ipId );
    } else {
        warning( sprintf( 'Unknown action (%s) for server IP with ID %s', $self->{'_data'}->{'ip_status'}, $ipId ));
        return 0;
    }

    eval {
        local $self->{'_dbh'}->{'RaiseError'} = 1;
        $self->{'_dbh'}->do( @sql );
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    $rs;
}

=back

=head1 PRIVATES METHODS

=over 4

=item _loadData( $ipId )

 Load data

 Param int $ipId Server IP unique identifier
 Return data on success, croak on failure

=cut

sub _loadData
{
    my ($self, $ipId) = @_;

    eval {
        local $self->{'_dbh'}->{'RaiseError'} = 1;
        $self->{'_data'} = $self->{'_dbh'}->selectrow_hashref(
            'SELECT ip_id, ip_card, ip_number AS ip_address, ip_netmask, ip_config_mode, ip_status FROM server_ips WHERE ip_id = ?', undef, $ipId
        );
        $self->{'_data'} or croak( sprintf( 'Data not found for server IP address (ID %d)', $ipId ));
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item _getData( $action )

 Data provider method for servers and packages

 Param string $action Action
 Return hashref Reference to a hash containing data

=cut

sub _getData
{
    my ($self, $action) = @_;

    $self->{'_data'}->{'action'} = $action;
    $self->{'_data'};
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
