<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:chpNS="http://www.biopac.com/ChannelPresets" version="1.0" >
	<xsl:template match="/">
		<html>
			<body>
				<h1 align="center">Analog Channel Presets Summary</h1>
				<table align="center" border="1">
					<tr bgcolor="blue">
            <th align="center">MP device</th>
            <th align="center">Preset Name</th>
						<th align="center">UID</th>
						<th align="center">Units</th>
					</tr>
          <xsl:value-of select="chpNS:channelpresetcollection/chpNS:calcpresetcollection"/>
					<xsl:for-each select="chpNS:channelpresetcollection/chpNS:analogpresetcollection/chpNS:analogpreset">
          <xsl:sort select="chpNS:hardwareconfig/@type" data-type="text" order="ascending" />
          <xsl:sort select="chpNS:presetlabel" data-type="text" order="ascending" />
						<tr>
              <td>MP<xsl:value-of select="chpNS:hardwareconfig/@type"/></td>
							<td><xsl:value-of select="chpNS:presetlabel"/></td>
							<td><b><xsl:value-of select="@uid"/></b></td>
							<td><xsl:value-of select="chpNS:unitslabel"/></td>
						</tr>
					</xsl:for-each>
				</table>
			</body>
		</html>
	</xsl:template>
</xsl:stylesheet>