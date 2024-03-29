﻿<?xml version="1.0" encoding="UTF-8" ?>

<%@ Page Language="C#" AutoEventWireup="true" Inherits="Composite_content_views_log_log" CodeFile="log.aspx.cs" %>
<%@ Register TagPrefix="aspui" Namespace="Composite.Core.WebClient.UiControlLib" Assembly="Composite" %>

<html xmlns="http://www.w3.org/1999/xhtml" xmlns:ui="http://www.w3.org/1999/xhtml">
	<control:httpheaders runat="server" />
	<head>
		<title>Composite.Management.ServerLog</title>
		<control:styleloader runat="server" />
		<control:scriptloader type="sub" runat="server" />
		<link rel="stylesheet" type="text/css" href="log.css.aspx" />
		<script type="text/javascript">
		    DocumentManager.isDocumentSelectable = true;
		</script>
	</head>
	<body>
		<form id="Form1" runat="server">
			<ui:page label="${string:ServerLog.LabelTitle}" image="${icon:log-showlog}">
				<ui:toolbar id="toolbar">
					<ui:toolbarbody>
						<ui:toolbargroup>
							<aspui:Selector runat="server" ID="Pager" AutoPostBack="true" OnSelectedIndexChanged="LogContentChanged" />
							<aspui:ToolbarButton ID="DeleteOlderButton" AutoPostBack="true" Text="${string:ServerLog.LabelButtonDeleteOld}" ImageUrl="${icon:package-installer-uninstall}" runat="server" OnClick="DeleteOldButton_Click" />
							<aspui:ToolbarButton AutoPostBack="true" Text="${string:ServerLog.LabelButtonRefresh}" ImageUrl="${icon:refresh}" runat="server" OnClick="LogContentChanged" />
						</ui:toolbargroup>
						<ui:toolbargroup>
						    
                            <div class="left">
                                <aspui:CheckBox runat="server" ItemLabel="${string:ServerLog.Severity.Critical}" ID="chkCritical" Checked="True" />
                            </div>
                            <div class="left">
                                <aspui:CheckBox runat="server" ItemLabel="${string:ServerLog.Severity.Error}" ID="chkError" Checked="True" />
                            </div>
                            <div class="left">
                                <aspui:CheckBox runat="server" ItemLabel="${string:ServerLog.Severity.Warning}" ID="chkWarning" Checked="True" />
                            </div>
                            <div class="left">
                                <aspui:CheckBox runat="server" ItemLabel="${string:ServerLog.Severity.Information}" ID="chkInformation" Checked="True" />
                            </div>
                            <div class="left">
                                <aspui:CheckBox runat="server" ItemLabel="${string:ServerLog.Severity.Verbose}" ID="chkVerbose" Checked="False" />
                            </div>
                            
						</ui:toolbargroup>
					</ui:toolbarbody>
				</ui:toolbar>
				<ui:scrollbox id="scrollbox">
					<asp:PlaceHolder ID="LogHolder" runat="server" />
					<asp:PlaceHolder runat="server" ID="EmptyLabelPlaheHolder" Visible="false">
						<div id="emptylabel"><ui:text label="${string:ServerLog.EmptyLabel}"/></div>
					</asp:PlaceHolder>
				</ui:scrollbox>
			</ui:page>
		</form>
	</body>
</html>
