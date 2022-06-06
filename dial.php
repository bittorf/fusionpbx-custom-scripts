<?php

error_reporting(E_ALL ^ E_NOTICE);	# meldet alle fehler ausser E_NOTICE = vorgabe von php.ini

print("<html><head>");
print("");
print("<script type=\"text/javascript\">");
print("<!--");
print("function sleep_and_close(milliseconds) {");
print("  var start = new Date().getTime();");
print("  for (var i = 0; i < 1e7; i++) {");
print("    if ((new Date().getTime() - start) > milliseconds){");
print("      window.close()");
print("      break;");
print("    }");
print("  }");
print("}");
print("//-->");
print("</script>");
print("");
print("<title>VoIP</title></head><body onload=\"sleep_and_close(10000)\">");

function ip_is_rfc1918($IP){
	if (substr($IP, 0, 3) == '10.') return true;
	if (substr($IP, 0, 7) == '172.17.') return true;
	if (substr($IP, 0, 8) == '192.168.') return true;

	return false;
}

// noetig fuer
// 827 142  Konstanze Illmer
// 827 144  Arlett Symanowski
// 862 332  Praktikant
// 827 405  Gast5?

$IP = $_SERVER["REMOTE_ADDR"];		// from script-caller
if(!ip_is_rfc1918($IP)) {
	print("not allowed from your IP: $IP");
	print("</body></html>");
	exit;
}

if(isset($_GET["number"])) {           // dial='true'
	$number = strval($_GET["number"]);
	$extension = strval($_GET["extension"]);

	print("OK, w&aumlhle jetzt die Nummer $number von der Nebenstelle $extension<br><br>");
	system("/usr/local/bin/dial.sh '".$number."' '".$extension."'");
	print("</body></html>");
	exit;
};

print("please use e.g. https://$ip/dial.php?extension=405&number=017624223419");
print("</body></html>");

?>
