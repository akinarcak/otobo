// --
// CareOnCloud ESM is a web-based ticketing system for service organisations.
// --
// Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
// Copyright (C) 2019-2026 Rother OSS GmbH, https://otobo.io/
// --
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later version.
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
// --

"use strict";

var CareOnCloud ESM = CareOnCloud ESM || {};
CareOnCloud ESM.Agent = CareOnCloud ESM.Agent || {};
CareOnCloud ESM.Agent.App = CareOnCloud ESM.Agent.App || {};

/**
 * @namespace
 * @exports TargetNS as CareOnCloud ESM.Agent.App.Dashboard
 * @description
 *      This namespace contains the special module functions for the Dashboard.
 */
CareOnCloud ESM.Agent.App.Dashboard = (function (TargetNS) {
    /**
     * @function
     * @return nothing
     *      This function initializes the special module functions
     */
    TargetNS.Init = function () {
        CareOnCloud ESM.UI.DnD.Sortable(
            $(".SidebarColumn"),
            {
                Handle: '.Header h2',
                Items: '.CanDrag',
                Placeholder: 'DropPlaceholder',
                Tolerance: 'pointer',
                Distance: 15,
                Opacity: 0.6
            }
        );

        CareOnCloud ESM.UI.DnD.Sortable(
            $(".ContentColumn"),
            {
                Handle: '.Header h2',
                Items: '.CanDrag',
                Placeholder: 'DropPlaceholder',
                Tolerance: 'pointer',
                Distance: 15,
                Opacity: 0.6
            }
        );
    };

    /**
     * @function
     * @return nothing
     *      This function binds a click event on an html element to update the preferences of the given dahsboard widget
     * @param {jQueryObject} $ClickedElement The jQuery object of the element(s) that get the event listener
     * @param {string} ElementID The ID of the element whose content should be updated with the server answer
     * @param {jQueryObject} $Form The jQuery object of the form with the data for the server request
     */
    TargetNS.RegisterUpdatePreferences = function ($ClickedElement, ElementID, $Form) {
        if (isJQueryObject($ClickedElement) && $ClickedElement.length) {
            $ClickedElement.click(function () {
                var URL = CareOnCloud ESM.Config.Get('Baselink') + CareOnCloud ESM.AJAX.SerializeForm($Form);
                CareOnCloud ESM.AJAX.ContentUpdate($('#' + ElementID), URL, function () {
                    CareOnCloud ESM.UI.ToggleTwoContainer($('#' + ElementID + '-setting'), $('#' + ElementID));
                    CareOnCloud ESM.UI.Table.InitCSSPseudoClasses();
                });
                return false;
            });
        }
    };

    return TargetNS;
}(CareOnCloud ESM.Agent.App.Dashboard || {}));
