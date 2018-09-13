=head1 NAME

 iMSCP::Package::Installer::FileManager::MonstaFTP - i-MSCP package

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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

package iMSCP::Package::Installer::FileManager::MonstaFTP;

use strict;
use warnings;
use iMSCP::Boolean;
use iMSCP::Composer;
use iMSCP::Debug 'error';
use iMSCP::Dir;
use iMSCP::File;
use iMSCP::Package::Installer::FrontEnd;
use iMSCP::Rights 'setRights';
use iMSCP::TemplateParser qw/ getBlocByRef replaceBlocByRef /;
use JSON;
use parent 'iMSCP::Package::Abstract';

our $VERSION = '2.1.x';

=head1 DESCRIPTION

 i-MSCP MonstaFTP package.

 MonstaFTP is a web-based FTP client written in PHP.

 Project homepage: http://www.monstaftp.com//

=head1 PUBLIC METHODS

=over 4

=item preinstall( )

 See iMSCP::Installer::AbstractActions::preinstall()

=cut

sub preinstall
{
    my ( $self ) = @_;

    my $rs = iMSCP::Composer->getInstance()->registerPackage( 'imscp/monsta-ftp', $VERSION );
    $rs ||= $self->{'eventManager'}->register( 'afterFrontEndBuildConfFile', \&afterFrontEndBuildConfFile );
}

=item install( )

 See iMSCP::Installer::AbstractActions::install()

=cut

sub install
{
    my ( $self ) = @_;

    my $rs = $self->_installFiles();
    $rs ||= $self->_buildHttpdConfig();
    $rs ||= $self->_buildConfig();
}

=item uninstall( )

 See iMSCP::Uninstaller::AbstractActions::uninstall()

=cut

sub uninstall
{
    my ( $self ) = @_;

    my $rs = $self->_unregisterConfig();
    $rs ||= $self->_removeFiles();
}

=item setGuiPermissions( )

 See iMSCP::Installer::AbstractActions::setGuiPermissions()

=cut

sub setGuiPermissions
{
    my ( $self ) = @_;

    my $panelUserGroup = $::imscpConfig{'SYSTEM_USER_PREFIX'} . $::imscpConfig{'SYSTEM_USER_MIN_UID'};

    setRights( "$::imscpConfig{'GUI_PUBLIC_DIR'}/tools/ftp", {
        user      => $panelUserGroup,
        group     => $panelUserGroup,
        dirmode   => '0550',
        filemode  => '0440',
        recursive => TRUE
    } );
}

=back

=head1 EVENT LISTENERS

=over 4

=item afterFrontEndBuildConfFile( \$tplContent, $filename )

 Include httpd configuration into frontEnd vhost files

 Param string \$tplContent Template file tplContent
 Param string $tplName Template name
 Return int 0 on success, other on failure

=cut

sub afterFrontEndBuildConfFile
{
    my ( $tplContent, $tplName ) = @_;

    return 0 unless grep ($_ eq $tplName, '00_master.nginx', '00_master_ssl.nginx');

    replaceBlocByRef(
        "# SECTION custom BEGIN.\n",
        "# SECTION custom END.\n",
        "    # SECTION custom BEGIN.\n"
            . getBlocByRef( "# SECTION custom BEGIN.\n", "# SECTION custom END.\n", $tplContent )
            . "    include imscp_monstaftp.conf;\n"
            . "    # SECTION custom END.\n",
        $tplContent
    );
    0;
}

=back

=head1 PRIVATE METHODS

=over 4

=item _installFiles( )

 Install MonstaFTP files in production directory

 Return int 0 on success, other or die on failure

=cut

sub _installFiles
{
    my $packageDir = "$::imscpConfig{'IMSCP_HOMEDIR'}/packages/vendor/imscp/monsta-ftp";

    unless ( -d $packageDir ) {
        error( "Couldn't find the imscp/monsta-ftp package into the packages cache directory" );
        return 1;
    }

    iMSCP::Dir->new( dirname => "$::imscpConfig{'GUI_PUBLIC_DIR'}/tools/ftp" )->remove();
    iMSCP::Dir->new( dirname => "$packageDir/src" )->rcopy( "$::imscpConfig{'GUI_PUBLIC_DIR'}/tools/ftp", { preserve => 'no' } );
    iMSCP::Dir->new( dirname => "$packageDir/iMSCP/src" )->rcopy( "$::imscpConfig{'GUI_PUBLIC_DIR'}/tools/ftp", { preserve => 'no' } );
}

=item _buildHttpdConfig( )

 Build Httpd configuration

 Return int 0 on success, other on failure

=cut

sub _buildHttpdConfig
{
    my $frontEnd = iMSCP::Package::Installer::FrontEnd->getInstance();
    $frontEnd->buildConfFile(
        "$::imscpConfig{'IMSCP_HOMEDIR'}/packages/vendor/imscp/monsta-ftp/iMSCP/nginx/imscp_monstaftp.conf",
        { GUI_PUBLIC_DIR => $::imscpConfig{'GUI_PUBLIC_DIR'} },
        { destination => "$frontEnd->{'config'}->{'HTTPD_CONF_DIR'}/imscp_monstaftp.conf" }
    );
}

=item _buildConfig( )

 Build configuration file

 Return int 0 on success, other on failure

=cut

sub _buildConfig
{
    my ( $self ) = @_;

    # config.php file

    my $conffile = "$::imscpConfig{'GUI_PUBLIC_DIR'}/tools/ftp/settings/config.php";
    my $data = {
        TIMEZONE => ::setupGetQuestion( 'TIMEZONE', 'UTC' ),
        TMP_PATH => "$::imscpConfig{'GUI_ROOT_DIR'}/data/tmp"
    };

    my $rs = $self->{'eventManager'}->trigger( 'onLoadTemplate', 'monstaftp', 'config.php', \my $cfgTpl, $data );
    return $rs if $rs;

    unless ( defined $cfgTpl ) {
        $cfgTpl = iMSCP::File->new( filename => $conffile )->get();
        return 1 unless defined $cfgTpl;
    }

    $cfgTpl = process( $data, $cfgTpl );

    my $panelUserGroup = $::imscpConfig{'SYSTEM_USER_PREFIX'} . $::imscpConfig{'SYSTEM_USER_MIN_UID'};
    my $file = iMSCP::File->new( filename => $conffile );
    $file->set( $cfgTpl );
    $rs = $file->save();
    $rs ||= $file->owner( $panelUserGroup, $panelUserGroup );
    $rs ||= $file->mode( 0440 );
    return $rs if $rs;

    $conffile = "$::imscpConfig{'GUI_PUBLIC_DIR'}/tools/ftp/settings/settings.json";
    $data = {
        showDotFiles            => JSON::true,
        language                => 'en_us',
        editNewFilesImmediately => JSON::true,
        editableFileExtensions  => 'txt,htm,html,php,asp,aspx,js,css,xhtml,cfm,pl,py,c,cpp,rb,java,xml,json',
        hideProUpgradeMessages  => JSON::true,
        disableMasterLogin      => JSON::true,
        connectionRestrictions  => {
            types => [ 'ftp' ],
            ftp   => {
                host             => '127.0.0.1',
                port             => 21,
                # Enable passive mode excepted if the FTP daemon is vsftpd
                # vsftpd doesn't allows to operate on a per IP basic (IP masquerading)
                passive          => $::imscpConfig{'FTPD_SERVER'} eq 'vsftpd' ? JSON::false : JSON::true,
                ssl              => ::setupGetQuestion( 'SERVICES_SSL_ENABLED' ) eq 'yes' ? JSON::true : JSON::false,
                initialDirectory => '/' # Home directory as set for the FTP user
            }
        }
    };

    undef $cfgTpl;
    $rs = $self->{'eventManager'}->trigger( 'onLoadTemplate', 'monstaftp', 'settings.json', \$cfgTpl, $data );
    return $rs if $rs;

    $file = iMSCP::File->new( filename => $conffile );
    $file->set( $cfgTpl || JSON->new()->utf8( 1 )->pretty( 1 )->encode( $data ));
    $rs = $file->save();
    $rs ||= $file->owner( $panelUserGroup, $panelUserGroup );
    $rs ||= $file->mode( 0440 );
}

=item _unregisterConfig( )

 Remove include directive from frontEnd vhost files

 Return int 0 on success, other on failure

=cut

sub _unregisterConfig
{
    my ( $self ) = @_;

    my $frontEnd = iMSCP::Package::Installer::FrontEnd->getInstance();

    return 0 unless -f "$frontEnd->{'config'}->{'HTTPD_SITES_AVAILABLE_DIR'}/00_master.conf";

    my $file = iMSCP::File->new( filename => "$frontEnd->{'config'}->{'HTTPD_SITES_AVAILABLE_DIR'}/00_master.conf" );
    my $fileC = $file->getAsRef();
    return 1 unless defined $fileC;

    ${ $fileC } =~ s/[\t ]*include imscp_monstaftp.conf;\n//;

    my $rs = $file->save();
    return $rs if $rs;

    $frontEnd->{'reload'} = TRUE;
    0;
}

=item _removeFiles( )

 Remove files

 Return int 0 on success, other pr die on failure

=cut

sub _removeFiles
{
    my ( $self ) = @_;

    iMSCP::Dir->new( dirname => "$::imscpConfig{'GUI_PUBLIC_DIR'}/tools/ftp" )->remove();

    my $frontEnd = iMSCP::Package::Installer::FrontEnd->getInstance();

    return 0 unless -f "$frontEnd->{'config'}->{'HTTPD_CONF_DIR'}/imscp_monstaftp.conf";

    iMSCP::File->new( filename => "$frontEnd->{'config'}->{'HTTPD_CONF_DIR'}/imscp_monstaftp.conf" )->delFile();
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__