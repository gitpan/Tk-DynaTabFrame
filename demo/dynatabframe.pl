#!/usr/bin/perl -w

use Tk;
use Tk::DynaTabFrame;
use Tk::TextUndo;
use Tk::DialogBox;
use Tk::LabEntry;

my %frames = ();
my %texts = ();
my $tabno = 0;

my $l_MainWindow = MainWindow->new();

my $l_Window = $l_MainWindow->DynaTabFrame (-font => 'Arial 8', -raisecmd => \&raise_cb)
	->pack (-side => 'top', -expand => 1, -fill => 'both');

my $l_ButtonFrame = $l_MainWindow->Frame()->pack(-side => 'bottom', -fill => 'both', -expand => 0);

my $l_OK = $l_ButtonFrame->Button
   (
    -text => Ok,

    -command => sub
       {
        $l_MainWindow->destroy();
       }
   );

$l_OK->pack
   (
    -side => 'right',
    -anchor => 'ne',
    -fill => 'none',
    -padx => 10,
   );


my $l_Add = $l_ButtonFrame->Button
   (
    -text => 'Add Tab',

    -command => sub
       {
       		$tabno++;
       		my $caption = ($tabno == 1) ? 'Caption 1 for a really long caption' :
       			"Caption $tabno";

			$frames{$caption} = 
				$l_Window->add(-caption => $caption, -tabcolor => 'yellow');
			$texts{$caption} = $frames{$caption}->Scrolled('TextUndo', -scrollbars => 'osoe',
				-width => 50, -height => 30, -wrap => 'none',
				-font => 'Courier 10')->pack(-fill => 'both', -expand => 1);
			$texts{$caption}->insert('end', "This is the $tabno tabframe");
       }
   );

$l_Add->pack
   (
    -side => 'right',
    -anchor => 'ne',
    -fill => 'none',
    -padx => 10,
   );
#
#	remove only the raised tab
#
my $l_Remove = $l_ButtonFrame->Button
   (
    -text => 'Remove Tab',

    -command => sub
       {
       	my $caption = $l_Window->raised_name();
       	return 1 unless $caption;
       	
        delete $frames{$caption};
        delete $texts{$caption};
        $l_Window->delete($caption);
       }
   );

$l_Remove->pack
   (
    -side => 'right',
    -anchor => 'ne',
    -fill => 'none',
    -padx => 10,
   );

my $l_Raise = $l_ButtonFrame->Button
   (
    -text => 'Raise...',

    -command => \&raise_tab
   );

$l_Raise->pack
   (
    -side => 'right',
    -anchor => 'ne',
    -fill => 'none',
    -padx => 10,
   );

my $l_Cancel = $l_ButtonFrame->Button
   (
    -text => Cancel,
    -command => sub {$l_MainWindow->destroy();}
   );

$l_Cancel->pack
   (
    -side => 'left',
    -anchor => 'nw',
    -fill => 'none',
    -padx => 10,
   );

my $l_Lock = $l_ButtonFrame->Button
   (
    -text => 'Lock',
    -command => sub { tablock(); }
   );

$l_Lock->pack
   (
    -side => 'left',
    -anchor => 'nw',
    -fill => 'none',
    -padx => 10,
   );

my $l_Tabs = $l_ButtonFrame->Button
   (
    -text => 'Get Tabs',
    -command => sub {my $tabs = $l_Window->cget(-tabs); print join(', ', keys %$tabs), "\n";}
   );

$l_Tabs->pack
   (
    -side => 'left',
    -anchor => 'nw',
    -fill => 'none',
    -padx => 10,
   );


Tk::MainLoop();

sub tablock {
   	if ($l_Lock->cget(-text) eq 'Lock') {
   		$l_Lock->configure(-text => 'Unlock');
   		$l_Window->configure(-tablock => 1);
   	}
   	else {
   		$l_Lock->configure(-text => 'Lock');
   		$l_Window->configure(-tablock => undef);
   	}
}

sub raise_cb { print shift, "\n"; }

sub raise_tab {
#
#	create dialog to enter a tab text
#
	my $dlg = $l_MainWindow->DialogBox(
		-title => 'Enter Tab to Raise', 
		-buttons => [ 'OK', 'Cancel' ],
		-default_button => 'OK');
	my $caption;
	$dlg->add('LabEntry' , 
		-textvariable => \$caption, 
		-width => 40,
		-background => 'white',
		-label => 'Tab Name',
		-labelPack => [ -side => 'left'])
		->pack;
	my $answer = $dlg->Show();
	return 1 if ($answer eq 'Cancel');
	
	$l_Window->raise($caption);
	1;
}