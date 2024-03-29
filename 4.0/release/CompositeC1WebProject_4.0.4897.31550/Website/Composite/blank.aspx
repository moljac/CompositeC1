<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:control="http://www.composite.net/ns/uicontrol">
    
<%@ Page Language="C#" %>

	<control:httpheaders runat="server"/>
	<head>
		<title>Composite.Management.Blank</title>
		<control:styleloader runat="server"/>
		<control:scriptloader type="sub" runat="server" />
		<script type="text/javascript">
			window.isDefaultDocument = true;
		</script>
	</head>
	<body>
		<!-- 
			for HTTPS setup, XPSP2 will complain about loading "about:blank" in iframes 
			so please use this page as default content. 
		-->
	</body>
</html>