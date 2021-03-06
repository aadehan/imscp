<?php
/**
 * i-MSCP - internet Multi Server Control Panel
 * Copyright (C) 2010-2019 by Laurent Declercq <l.declercq@nuxwin.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

/**
 * @noinspection
 * PhpDocMissingThrowsInspection
 * PhpUnhandledExceptionInspection
 * PhpIncludeInspection
 */

use iMSCP\Event\Event;
use iMSCP\Event\EventAggregator;
use iMSCP\Event\Events;
use iMSCP\TemplateEngine;

/**
 * Genrate statistics entry for the given user
 *
 * @param TemplateEngine $tpl Template engine instance
 * @param int $adminId User unique identifier
 * @return void
 */
function _generateUserStatistics(TemplateEngine $tpl, $adminId)
{
    list($webTraffic, $ftpTraffic, $smtpTraffic, $pop3Traffic, $trafficUsage, $diskUsage
        ) = getClientTrafficAndDiskStats($adminId);
    list($subCount, $subLimit, $alsCount, $alsLimit, $mailCount, $mailLimit, $ftpCount, $ftpLimit, $sqlDbCount,
        $sqlDbLimit, $sqlUsersCount, $sqlUsersLlimit, $trafficLimit, $diskLimit
        ) = getClientItemCountsAndLimits($adminId);
    $trafficUsagePercent = getPercentUsage($trafficUsage, $trafficLimit);
    $diskspaceUsagePercent = getPercentUsage($diskUsage, $diskLimit);
    $tpl->assign([
        'USER_NAME'             => tohtml(decode_idna(get_user_name($adminId))),
        'USER_ID'               => tohtml($adminId),
        'TRAFFIC_PERCENT_WIDTH' => tohtml($trafficUsagePercent, 'htmlAttr'),
        'TRAFFIC_PERCENT'       => tohtml($trafficUsagePercent),
        'TRAFFIC_MSG'           => ($trafficLimit > 0)
            ? tohtml(sprintf('%s / %s', bytesHuman($trafficUsage), bytesHuman($trafficLimit)))
            : tohtml(sprintf('%s / ∞', bytesHuman($trafficUsage))),
        'DISK_PERCENT_WIDTH'    => tohtml($diskspaceUsagePercent, 'htmlAttr'),
        'DISK_PERCENT'          => tohtml($diskspaceUsagePercent),
        'DISK_MSG'              => ($diskLimit > 0)
            ? tohtml(sprintf('%s / %s', bytesHuman($diskUsage), bytesHuman($diskLimit)))
            : tohtml(sprintf('%s / ∞', bytesHuman($diskUsage))),
        'WEB'                   => tohtml(bytesHuman($webTraffic)),
        'FTP'                   => tohtml(bytesHuman($ftpTraffic)),
        'SMTP'                  => tohtml(bytesHuman($smtpTraffic)),
        'POP3'                  => tohtml(bytesHuman($pop3Traffic)),
        'SUB_MSG'               => tohtml(sprintf('%s / %s', $subCount, translate_limit_value($subLimit))),
        'ALS_MSG'               => tohtml(sprintf('%s / %s', $alsCount, translate_limit_value($alsLimit))),
        'MAIL_MSG'              => tohtml(sprintf('%s / %s', $mailCount, translate_limit_value($mailLimit))),
        'FTP_MSG'               => tohtml(sprintf('%s / %s', $ftpCount, translate_limit_value($ftpLimit))),
        'SQL_DB_MSG'            => tohtml(sprintf('%s / %s', $sqlDbCount, translate_limit_value($sqlDbLimit))),
        'SQL_USER_MSG'          => tohtml(sprintf('%s / %s', $sqlUsersCount, translate_limit_value($sqlUsersLlimit)))
    ]);
}

/**
 * Generates page
 *
 * @param TemplateEngine $tpl Template engine instance
 * @param int $resellerId Reseller unique identifier
 * @return void
 */
function generatePage(TemplateEngine $tpl, $resellerId)
{
    $stmt = exec_query('SELECT admin_id FROM admin WHERE created_by = ?', $resellerId);

    if (!$stmt->rowCount()) {
        $tpl->assign('RESELLER_USER_STATISTICS_BLOCK', '');
        return;
    }

    while ($row = $stmt->fetchRow()) {
        _generateUserStatistics($tpl, $row['admin_id']);
        $tpl->parse('RESELLER_USER_STATISTICS_BLOCK', '.reseller_user_statistics_block');
    }
}

require 'imscp-lib.php';

check_login('admin');
EventAggregator::getInstance()->dispatch(Events::onAdminScriptStart);

if (isset($_GET['reseller_id'])) {
    $resellerId = intval($_GET['reseller_id']);
    $_SESSION['stats_reseller_id'] = $resellerId;
} elseif (isset($_SESSION['stats_reseller_id'])) {
    redirectTo('reseller_user_statistics.php?reseller_id=' . $_SESSION['stats_reseller_id']);
    exit;
} else {
    showBadRequestErrorPage();
    exit;
}

$tpl = new TemplateEngine();
$tpl->define_dynamic([
    'layout'                         => 'shared/layouts/ui.tpl',
    'page'                           => 'admin/reseller_user_statistics.tpl',
    'page_message'                   => 'layout',
    'reseller_user_statistics_block' => 'page'
]);
$tpl->assign([
    'TR_PAGE_TITLE'             => tohtml(tr('Admin / Statistics / Reseller Statistics / User Statistics')),
    'TR_USERNAME'               => tohtml(tr('User')),
    'TR_TRAFF'                  => tohtml(tr('Monthly traffic usage')),
    'TR_DISK'                   => tohtml(tr('Disk usage')),
    'TR_WEB'                    => tohtml(tr('HTTP traffic')),
    'TR_FTP_TRAFF'              => tohtml(tr('FTP traffic')),
    'TR_SMTP'                   => tohtml(tr('SMTP traffic')),
    'TR_POP3'                   => tohtml(tr('POP3/IMAP traffic')),
    'TR_SUBDOMAIN'              => tohtml(tr('Subdomains')),
    'TR_ALIAS'                  => tohtml(tr('Domain aliases')),
    'TR_MAIL'                   => tohtml(tr('Mail accounts')),
    'TR_FTP'                    => tohtml(tr('FTP accounts')),
    'TR_SQL_DB'                 => tohtml(tr('SQL databases')),
    'TR_SQL_USER'               => tohtml(tr('SQL users')),
    'TR_DETAILED_STATS_TOOLTIP' => tohtml(tr('Show detailed statistics for this user'), 'htmlAttr')
]);

EventAggregator::getInstance()->registerListener(
    Events::onGetJsTranslations,
    function (Event $e) {
        $e->getParam('translations')->core['dataTable'] = getDataTablesPluginTranslations(false);
    }
);

generateNavigation($tpl);
generatePage($tpl, $resellerId);
generatePageMessage($tpl);

$tpl->parse('LAYOUT_CONTENT', 'page');
EventAggregator::getInstance()->dispatch(Events::onAdminScriptEnd, ['templateEngine' => $tpl]);
$tpl->prnt();

unsetMessages();
