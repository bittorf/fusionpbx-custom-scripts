<?php

// $EXTENSION = strval($_GET["EXTENSION"]);

$script = "/usr/local/bin/print_invoice.sh";

$EXTENSION          = strval($_GET["EXTENSION"]);
$START_MONTH_NUMBER = strval($_GET["START_MONTH_NUMBER"]);
$START_DAY_OF_MONTH = strval($_GET["START_DAY_OF_MONTH"]);
$START_YEAR         = strval($_GET["START_YEAR"]);
$END_MONTH_NUMBER   = strval($_GET["END_MONTH_NUMBER"]);
$END_DAY_OF_MONTH   = strval($_GET["END_DAY_OF_MONTH"]);
$END_YEAR           = strval($_GET["END_YEAR"]);

if(isset($_GET["EXTENSION"])) {
	$args = "'".$EXTENSION."' '".$START_MONTH_NUMBER."' '".$START_DAY_OF_MONTH."' '".$START_YEAR."' '".$END_MONTH_NUMBER."' '".$END_DAY_OF_MONTH."' '".$END_YEAR."'";
} else {
	$args = "'show_form'";
}

print "";
system($script." ".$args);

?>
