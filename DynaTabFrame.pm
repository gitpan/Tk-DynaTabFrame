package Tk::DynaTabFrame;

use Tk;
use Tk ':variables';

use base qw (Tk::Derived Tk::Frame);
use vars qw ($VERSION);
use strict;
use Carp;

$VERSION = '0.07';

Tk::Widget->Construct ('DynaTabFrame');

sub Populate
   {
    my $this = shift;
#
#	ButtonFrame is where the tabs are
#
    my $ButtonFrame = $this->{ButtonFrame} = $this->Component
       (
        'Frame' => 'ButtonFrame',
        '-borderwidth' => 0,
        '-relief' => 'flat',
        '-height' => 40,
       );

    $ButtonFrame->pack
       (
        -anchor => 'nw',
        -side => 'top',
        -fill => 'x',		# we may need to adjust this
       );
#
#	this is where we put our tabbed widget
#
    my $ClientFrame = $this->{ClientFrame} = $this->Component
       (
        'Frame' => 'TabChildFrame',
        '-relief' => 'flat',
        '-borderwidth' => 0,
        '-height' => 60,
       );

    $ClientFrame->pack
       (
        -side => 'bottom',
        -expand => 'true',
        -fill => 'both',
       );
#
#	a pseudo-frame used to make the raised tab smoothly connect
#	to the client frame
#
    my $MagicFrame = $this->Component
       (
        'Frame' => 'MagicFrame', -relief => 'flat'
       );

    $this->ConfigSpecs
       (
        '-borderwidth' => [['SELF', 'PASSIVE'], 'borderwidth', 'BorderWidth', '1'],
        '-tabcurve' => [['SELF', 'PASSIVE'], 'tabcurve', 'TabCurve', 2],
        '-padx' => [['SELF', 'PASSIVE'], 'padx', 'padx', 5],
        '-pady' => [['SELF', 'PASSIVE'], 'pady', 'pady', 5],
        '-font' => ['METHOD', 'font', 'Font', undef],
        '-current' => ['METHOD'],
        '-raised' => ['METHOD'],
        '-raised_name' => ['METHOD'],
        '-tabs' => ['METHOD'],
		'-delay' => [['SELF', 'PASSIVE'], 'delay', 'Delay', '200'],
		'-raisecmd' => [['SELF', 'PASSIVE'], 'raisecmd', 'RaiseCmd', undef],
        '-tablock' => [['SELF', 'PASSIVE'], 'tablock', 'tablock', undef],
        # These are historical. Their use is deprecated

        '-trimcolor' => ['PASSIVE', 'trimcolor','trimcolor', undef],
        '-bottomedge' => ['PASSIVE', 'bottomedge', 'BottomEdge', undef],
        '-sideedge' => ['PASSIVE', 'sideedge', 'SideEdge', undef],
        '-tabstart' => ['PASSIVE', 'tabstart', 'TabStart', undef],
       );

    $this->SUPER::Populate (@_);
#
#	list of all our current clients
#
	$this->{ClientList} = [ ];
#
#	a quick lookup by caption
#
	$this->{ClientHash} = {};
#
#	a cache for our pseudotabs used to beautify
#	the right side of a tabrow
#	indexed by the row number, stores the
#	index of the client entry that holds the
#	pseudotab widgets...but none for row 0
#
	$this->{PseudoTabs} = [ undef ];
#
#	a quick lookup of row numbers
#	so a raise() can just move entire rows around
#	create first empty row
#
	$this->{RowList} = [ [] ];
#
#	plug into the configure event so we get resizes
#
	$this->{OldWidth} = $ButtonFrame->reqwidth();
	$this->bind("<Configure>" => sub { $this->ConfigDebounce; });

    return $this;
}

sub ConfigDebounce {
	my ($this) = @_;
	my $w = $Tk::event->w;
#
#	only post event if we've changed width significantly
#
	return 1 unless (
		(($w < $this->{OldWidth}) && ($this->{OldWidth} - $w > 13)) ||
		(($w > $this->{OldWidth}) && ($w - $this->{OldWidth} > 13)));

	$this->{LastConfig} = Tk::timeofday;
	$this->{LastWidth} = $w;

	$this->afterCancel($this->{LastAfterID})
		if defined($this->{LastAfterID});

	$this->{LastAfterID} = $this->after(200, # $this->cget('-delay'), 
		sub {
			$this->TabReconfig();
			delete $this->{LastAfterID};
		}
	);
	1;
}

sub TabCreate {
    my ($this, $Caption, $Color) = (shift, @_);
#
#	always add at (0,0)
#
	my $clients = $this->{ClientList};
	my $rows = $this->{RowList};
	my $ButtonFrame = $this->{ButtonFrame};
#
#	create a new frame for the caller
#
    my $Widget = $this->{ClientFrame}->Frame
       (
        '-borderwidth' => $this->cget ('-borderwidth'),
        '-relief' => 'raised',
       );
#
#	create a new frame for a tab
#
    my $TabFrame = $ButtonFrame->Component
       (
        'Frame' => 'Button_'.$Widget,
        '-foreground' => $this->cget ('-foreground'),
        '-relief' => 'flat',
        '-borderwidth' => 0,
       );
#
#	build the tab for it; in future we may support images
#
	my $font = $this->cget(-font);
	$font = $this->parent()->cget(-font) unless $font;
    my $Button = $TabFrame->Component
       (
        'Button' => 'Button',
        -command => sub { $this->configure (-current => $Widget);},
        (defined ($Color) ? ('-bg' => $Color) : ()),
        -text => $Caption || $Widget->name(),
        -anchor => 'n',
        -relief => 'flat',
        -borderwidth => 0,
        -takefocus => 1,
        -padx => 2,
        -pady => 2,
       );

    $Button->configure(-font => $font) if $font;

    $TabFrame->bind ('<ButtonRelease-1>' => sub {$Button->invoke();});
    $Button->bind ('<FocusOut>', sub {$Button->configure ('-highlightthickness' => 0);});
    $Button->bind ('<FocusIn>', sub {$Button->configure ('-highlightthickness' => 1);});
    $Button->bind ('<Control-Tab>', sub {($this->children())[0]->focus();});
    $Button->bind ('<Return>' => sub {$Button->invoke();});
#
#	decorate the tab
#
    $this->TabBorder ($TabFrame);

    $Button->configure
       (
        -highlightcolor => $Button->Darken ($Button->cget (-background), 50),
        -activebackground => $Button->cget (-background),
       );

    $Button->pack
       (
        -expand => 1,
        -fill => 'both',
        -ipadx => 0,
        -ipady => 0,
        -padx => 3,
        -pady => 3,
       );
#
#	pack tab in our rowframe 0; redraw if needed
#	move everything over 1 column in bottom row
#
	foreach my $i (@{$rows->[0]}) {
		$clients->[$i]->[4]++;
	}
	unshift @{$rows->[0]}, scalar @$clients;
#
#	save the client frame, the caption, the tabcolor,
#	the current row/column coords of our tab, our tabframe,
#	and the original height of this tab; we'll be stretching
#	the button later during redraws
#
    push @$clients, [ $Widget, $Caption, $Color, 0, 0, $TabFrame, $Button->reqheight() ];
#
#	map the caption to its position in the client list,
#	so we can raise and delete it by reference
#
    $this->{ClientHash}->{$Caption} = $#$clients;
#
#	redraw everything
#
	$this->TabRedraw(1);
#
#	and raise us
#
    $this->TabRaise($Widget);
	return $Widget;
}

sub PseudoCreate {
    my ($this, $row) = @_;

	my $ButtonFrame = $this->{ButtonFrame};
#
#	create a new frame for a pseudotab
#
    my $TabFrame = $ButtonFrame->Component
       (
        'Frame' => "Button_$row",
        '-foreground' => $this->cget ('-foreground'),
        '-relief' => 'flat',
        '-borderwidth' => 0,
       );

    my $Button = $TabFrame->Component
       (
        'Button' => 'Button',
        -command => undef,
        -text => '',
        -anchor => 'n',
        -relief => 'flat',
        -borderwidth => 0,
        -takefocus => 1,
        -padx => 2,
        -pady => 2,
       );

    $Button->pack
       (
        -expand => 1,
        -fill => 'both',
        -ipadx => 0,
        -ipady => 0,
        -padx => 3,
        -pady => 3,
       );
#
#	decorate the tab
#
    $this->TabBorder ($TabFrame, 1);

	return $TabFrame;
}

sub TabRaise {
    my ($this, $Widget, $silent) = (shift, @_);
#
#	locate the tab row
#	if its not the first row, then we need to move rows around
#	and redraw
#	else just raise it
#
    my $ButtonFrame = $this->{ButtonFrame};
    my $TabFrame = $ButtonFrame->Subwidget ('Button_'.$Widget);
    my ($magicx, $magicw) = ($TabFrame->x, $TabFrame->Subwidget('Button')->reqwidth+5);
#
#	find our client
#
	my $clients = $this->{ClientList};
#
#	strange timing issue sometimes leaves a null
#	entry at our tail
#
	pop @$clients unless defined($clients->[-1]);

	my $client;
	my $raised = 0;
	$raised++ while (($raised <= $#$clients) && 
		($clients->[$raised]->[0] ne $Widget));
		
	return 1 unless ($raised <= $#$clients);
	$client = $clients->[$raised];
	my ($r, $c) = ($client->[3], $client->[4]);
	my $rows = $this->{RowList};
#
#	undraw the magicframe
#
    my $MagicFrame = $this->Subwidget ('MagicFrame');
	$MagicFrame->placeForget() if $this->{Raised};
	delete $this->{Raised};
#
#	3 cases:
#		we're already at row 0, so just raise
#		else rotate rows off bottom to top until
#			raised row is bottom row
#
	if ($r != 0) {
#
#	middle row, or last row that fills the frame:
#	move the preceding to top, and move the selected row
#	to the bottom
#
		my $rowcnt = $r;
		push(@$rows, (shift @$rows)),
		$rowcnt--
			while ($rowcnt);
#
#	update client coords
#
		foreach my $i (0..$#$rows) {
			foreach my $j (@{$rows->[$i]}) {
				$clients->[$j]->[3] = $i;
			}
		}
		$this->TabRedraw;
	}
#
#	first, lower everything below the raised tab
#	in row 0
#
	my $lowest = $raised;
	my $pseudos = $this->{PseudoTabs};
	foreach my $i (@{$rows->[0]}) {
		next if ($i == $raised);
		$clients->[$i]->[5]->lower($clients->[$lowest]->[5]);
		$lowest = $i;
	}
#
#	now lower everything below its left neighbor
#
	foreach my $i (1..$#$rows) {
		foreach my $j (@{$rows->[$i]}) {
			$clients->[$j]->[5]->lower($clients->[$lowest]->[5]);
			$lowest = $j;
		}
	}
#
#	now make all pseudos lower
#
	if ($#$pseudos > 0) {
		$pseudos->[1]->lower($clients->[$lowest]->[5]);
		foreach my $i (2..$#$rows) {
			$pseudos->[$i]->lower($pseudos->[$i-1]);
		}
	}
    $TabFrame->Subwidget ('Button')->focus();
    $TabFrame->Subwidget ('Button')->raise();
    $TabFrame->raise();
#
#	lower the current frame, and then raise the new one
#
	$Widget->place(-x => 0, -y => 0, -relheight => 1.0, -relwidth => 1.0);
	$this->{CurrentFrame} = $Widget;

	pop @$clients unless defined($clients->[-1]);
	foreach my $i (0..$#$clients) {
		next unless ($clients->[$i] && $clients->[$i]->[0] &&
			($clients->[$i]->[0] ne $Widget));
		$clients->[$i]->[0]->lower($Widget)
			if $clients->[$i]->[0];
	}
#
#	used to smoothly connect raised tab to client frame
#
    $MagicFrame->place
       (
        -x => $magicx,
        -y => $this->{ClientFrame}->rooty() - $this->rooty() - 1,
        -height => $this->{ClientFrame}->cget ('-borderwidth'),
        -width => $magicw,
        -anchor => 'nw',
       );

    $MagicFrame->configure ('-bg' => $TabFrame->cget ('-background'));
    $MagicFrame->raise ();
    $this->{Raised} = $Widget;
#
#	callback if defined && allowed
#
	unless ($silent) {
		my $raisecb = $this->cget(-raisecmd);
		&$raisecb($client->[1])
			if ($raisecb && (ref $raisecb) && (ref $raisecb eq 'CODE'));
	}
    return $Widget;
}

sub TabBorder {
    my ($this, $TabFrame, $forpseudo) = @_;
    my $LineWidth = $this->cget ('-borderwidth');
    my $Background = $this->cget ('-background');
    my $InnerBackground = $TabFrame->Darken ($Background, 120),
    my $Curve = $this->cget ('-tabcurve');

	my ($LeftOuterBorder, $LeftInnerBorder);
	
	unless ($forpseudo) {
#
#	only for real buttons
#
    	$LeftOuterBorder = $TabFrame->Frame
    	   (
    	    '-background' => 'white',
    	    '-borderwidth' => 0,
    	   );

    	$LeftInnerBorder = $TabFrame->Frame
    	   (
    	    '-background' => $InnerBackground,
    	    '-borderwidth' => 0,
    	   );
	}

    my $TopOuterBorder = $TabFrame->Frame
       (
        '-background' => 'white',
        '-borderwidth' => 0,
       );

    my $TopInnerBorder = $TabFrame->Frame
       (
        '-background' => $InnerBackground,
        '-borderwidth' => 0,
       );

    my $RightOuterBorder = $TabFrame->Frame
       (
        '-background' => 'black',
        '-borderwidth' => 0,
       );

    my $RightInnerBorder = $TabFrame->Frame
       (
        '-background' => $TabFrame->Darken ($Background, 80),
        '-borderwidth' => 0,
       );

	unless ($forpseudo) {
    	$LeftOuterBorder->place
    	   (
    	    '-x' => 0,
    	    '-y' => $Curve - 1,
    	    '-width' => $LineWidth,
    	    '-relheight' => 1.0,
    	   );

    	$LeftInnerBorder->place
    	   (
    	    '-x' => $LineWidth,
    	    '-y' => $Curve - 1,
    	    '-width' => $LineWidth,
    	    '-relheight' => 1.0,
    	   );
	}

    $TopInnerBorder->place
       (
        '-x' => $Curve - 1,
        '-y' => $LineWidth,
        '-relwidth' => 1.0,
        '-height' => $LineWidth,
        '-width' => - ($Curve * 2),
       );

    $TopOuterBorder->place
       (
        '-x' => $Curve - 1,
        '-y' => 0,
        '-relwidth' => 1.0,
        '-height' => $LineWidth,
        '-width' => - ($Curve * 2),
       );

    $RightOuterBorder->place
       (
        '-x' => - ($LineWidth),
        '-relx' => 1.0,
        '-width' => $LineWidth,
        '-relheight' => 1.0,
        '-y' => $Curve,
       );

    $RightInnerBorder->place
       (
        '-x' => - ($LineWidth * 2),
        '-width' => $LineWidth,
        '-relheight' => 1.0,
        '-y' => $Curve / 2,
        '-relx' => 1.0,
       );
   }

sub TabCurrent
   {
    return
       (
        defined ($_[1]) ?
        $_[0]->TabRaise ($_[0]->{Raised} = $_[1]) :
        $_[0]->{Raised}
       );
   }
#
#	returns the width of a row
#
sub GetButtonRowWidth {
    my ($Width, $this, $row) = (0, shift, shift, @_);

	return 0
		unless ($this->{RowList} && ($#{$this->{RowList}} >= $row));

	my $rowlist = $this->{RowList}->[$row];
	my $tablist = $this->{ClientList};
    foreach my $Client (@$rowlist) {
   		next unless defined($tablist->[$Client]);
        $Width += $tablist->[$Client]->[5]->Subwidget ('Button')->reqwidth() + 5;
	}

    return $Width ? $Width - 10 : 0;
}
#
#	returns the accumulated height of all our rows
#
sub GetButtonRowHeight {
    my ($Height, $this, $row) = (0, shift, shift, @_);

	return 0
		unless ($this->{RowList} && ($#{$this->{RowList}} >= $row));

	my $total_ht = 0;
	foreach my $i (0..$row) {
    	  $total_ht += $this->GetRowHeight($i);
	}
    return $total_ht;
}
#
#	returns the height of a single row
#
sub GetRowHeight {
    my ($Height, $this, $row) = (0, shift, shift, @_);
    my $ButtonFrame = $this->{ButtonFrame};

	return 0 
		unless ($this->{RowList} && ($#{$this->{RowList}} >= $row));

	my $rowlist = $this->{RowList}->[$row];
	my $tablist = $this->{ClientList};
	my $total_ht = 0;
	my $newht = 0;
   	foreach my $Client (@$rowlist) {
   		next unless defined($tablist->[$Client]);
   	    $newht = $tablist->[$Client]->[6];
   	    $Height = $newht if ($newht > $Height);
	}
    return $Height;
}

sub Font {
    my ($this, $Font) = (shift, @_);

	my $font = $this->{Font};
	$font = $this->parent()->cget(-font) unless $font;

    return ($font) 
    	unless (defined ($Font));

    my $tablist = $this->{ClientList};

    foreach my $Client (@$tablist) {
        $Client->[5]->Subwidget ('Button')->configure(-font => $Font);
    }
#
#	we need to redraw, since this may change our tab layout
#
	$this->TabRedraw(1);
    return ($this->{Font} = $Font);
}
#
#	Reconfigure the tabs on resize event
#
sub TabReconfig {
	my ($this, $force) = @_;
  	return 1 if ($this->{Updating} || $this->cget(-tablock));
#
#	get current frame width
#
#  	my $w = $this->{ButtonFrame}->reqwidth();
	my $w = $this->{LastWidth};
  	my $oldwidth = $this->{OldWidth};
#
#	return unless significantly different from old size
#
  	return 1 if ((! $force) && defined($oldwidth) && 
  		(($oldwidth == $w) ||
  		(($oldwidth > $w) && ($oldwidth - $w < 10)) ||
  		(($oldwidth < $w) && ($w - $oldwidth < 10))));
  	$this->{OldWidth} = $w;
#
#	just redraw everything
#
	$this->{Updating} = 1;
	$this->TabRedraw(1);
	$this->{ClientFrame}->configure(-width => $w);
	$this->{Updating} = undef;
  	1;
  }
#
#	redraw our tabs
#
sub TabRedraw {
	my ($this, $rearrange) = @_;
#
#	compute new display ordering
#
	return 1 unless ($#{$this->{ClientList}} >= 0);
	my $ButtonFrame = $this->{ButtonFrame};
	my $clients = $this->{ClientList};
	my $rows = $this->{RowList};
#
#	if nothing to draw, bail out
#
	return 1 if (($#$rows < 0) || 
		(($#$rows == 0) && ($#{$rows->[0]} < 0)));

	my $pseudos = $this->{PseudoTabs};
	my @pseudowidths = ( 0 );
	my $Raised = $this->{Raised};	# save for later
	my $roww = 0;
	my $raised_row = undef;
	my $w = $ButtonFrame->width();

	if ($rearrange) {
#
#	rearrange tabs to fit new frame width
#
		my @newrows = ([]);
		foreach my $row (@$rows) {
			foreach my $i (@$row) {
				my $client = $clients->[$i];
			    my $TabFrame = $client->[5];
			    my $Button = $TabFrame->Subwidget('Button');
				my $btnw = ($Button->reqwidth() || 20) + 5;
				my $row = $#$rows;
		
				$roww = 0,
				push @newrows, [ ]
					if (($roww + $btnw > $w) && ($#{$newrows[0]} >= 0));

				$roww += $btnw;
				push @{$newrows[-1]}, $i;
				$client->[3] = $#newrows;
				$client->[4] = $#{$newrows[-1]};
				$raised_row = $#newrows 
					if ($Raised && $client->[0] && ($client->[0] eq $Raised));
			}
		}
#
#	save the new row lists
#
		$this->{RowList} = \@newrows;
		$rows = \@newrows;
	}
#
#	compute size of our pseudotabs
#
	foreach my $i (0..$#$rows) {
		push @pseudowidths, ($w - $this->GetButtonRowWidth($i));
#		print "Width of $i is ", $pseudowidths[-1], "\n";
#		push @pseudowidths, $w;
	}
#
#	purge all our pseudotabs
#
	foreach my $pseudo (@$pseudos) {
		next unless $pseudo;
		$pseudo->placeForget()
			if $pseudo->ismapped();
		$pseudo->destroy;
	}
	$this->{PseudoTabs} = $pseudos = [ undef ];
#
#	now create new ones
#
	foreach my $i (1..$#$rows) {
		push @$pseudos, $this->PseudoCreate($i);
	}
#
#	undraw all our buttons
#
	foreach my $i (0..$#$rows) {
		foreach my $j (@{$rows->[$i]}) {
			$clients->[$j]->[5]->placeForget()
				if $clients->[$j]->[5]->ismapped();
		}
	}
#
#	adjust our frame height to accomodate the rows
#
	my $y = $this->GetButtonRowHeight($#$rows) + 5;
	my $pseudoht;
	$ButtonFrame->configure(-height => $y);
#
#	reconfig tabs to match height of tallest tab in row
#
	foreach my $i (0..$#$rows) {
		$y = $this->GetRowHeight($i);
		foreach my $j (@{$rows->[$i]}) {
			$clients->[$j]->[5]->configure(-height => $y);
		}
#
#	reconfig any pseudotab for the row;
#	may need to redraw its border...
#
		if ($i) {
			$pseudoht = $this->GetButtonRowHeight($i-1) + 5;
			$pseudowidths[$i] = 0 unless ($pseudowidths[$i] > 0);
			$pseudos->[$i]->Subwidget('Button')->configure(-height => $pseudoht, 
				-width => $pseudowidths[$i]);
		}
	}
#
#	redraw all our buttons, starting from the top row
#	note: we force each button to fully fill the button frame;
#	this improves the visual effect when an upper tab extends
#	to the right of the end of the row below it
#
    my $MagicFrame = $this->Subwidget ('MagicFrame');
    $MagicFrame->placeForget() if $Raised;
	$y = 0;
	my $i = $#$rows;
	while ($i >= 0) {
		my $x = 0;
		foreach my $j (0..$#{$rows->[$i]}) {
			my $client = $clients->[$rows->[$i]->[$j]];
			$client->[5]->place(-x => $x, -y => $y);

			$x += $client->[5]->Subwidget('Button')->reqwidth + 5;
		}
#
#	draw pseudotabs if needed
#
		$y += $this->GetRowHeight($i);
		$pseudos->[$i]->place(-x => $x, -y => $y + 5) if $i;
		$i--;
	}
#
#	and reapply our tab order
#
	$this->TabOrder;
#
#	and reraise in case raised ended up somewhere other than
#	bottom row
#
	$this->TabRaise($Raised, 1) if $Raised;

	return 1;
}
#
#	remove a single tab and re-org the tabs
#
sub TabRemove {
	my ($this, $Caption) = @_;
	$this->{Updating} = 1;
#
#	remove a tab
#
	return undef 
		unless defined($this->{ClientHash}->{$Caption});
	
	my $rows = $this->{RowList};
	my $clients = $this->{ClientList};
	my $listsz = $#$clients;
	my $clientno = $this->{ClientHash}->{$Caption};
	my $client = $clients->[$clientno];
	my $Widget = $client->[0];
	my ($r, $c) = ($client->[3], $client->[4]);
#
#	if its the raised widget, then we need to raise 
#	a tab to replace it (unless its the only widget)
#	...whatever is left at 0,0 sounds good to me...
#
	my $row = $rows->[$r];
	my $newcurrent = ($client->[0] eq $this->{Raised}) ? 1 : undef;
#
#	remove client from lists
#
	delete $this->{ClientHash}->{$Caption};
	
	if ($clientno eq $#$clients) {
		pop @$clients;	# Perl bug ? we seem to not get spliced out at ends
	}
	else {
		splice @$clients, $clientno, 1;
	}
	splice @$row, $c, 1;
#
#	adjust client positions in this row
#
	foreach my $i ($c..$#$row) {
		$clients->[$row->[$i]]->[4]--;
	}
#
#	adjust client indices in the hash
#
	foreach my $i (keys %{$this->{ClientHash}}) {
		next unless ($this->{ClientHash}->{$i} > $clientno);
		$this->{ClientHash}->{$i} -= 1;
	}
#
#	adjust all our row index lists
#
	foreach my $row (@$rows) {
		foreach my $i (0..$#$row) {
			$row->[$i]-- if ($row->[$i] > $clientno);
		}
	}
	
    my $TabFrame = $client->[5];
	$TabFrame->packForget();
	$TabFrame->destroy();
	$Widget->destroy();
#
#	if only tab in row, remove the row
#	and adjust the clients in following rows
#
	if ($#$row < 0) {
		foreach my $i ($r+1..$#$rows) {
			$row = $rows->[$i];
			foreach my $j (@$row) {
				$clients->[$j]->[3] -= 1;
			}
		}
		splice @$rows, $r, 1;
		
		$this->{PseudoTabs}->[$r]->placeForget(),
		$this->{PseudoTabs}->[$r]->destroy,
		splice @{$this->{PseudoTabs}}, $r, 1
			if ($r && $this->{PseudoTabs}->[$r]);
	}

	if ($#$rows < 0) {
#
#	no rows left, clear everything
#
		$this->{Raised} = undef;
		$this->Subwidget('MagicFrame')->placeForget();
		$this->{CurrentFrame} = undef;
	}
	elsif ($newcurrent) {
		$this->{Raised} = $clients->[$rows->[0]->[0]]->[0];
	}
#
#	redraw everything
#
	$this->TabRedraw(1);
	$this->{Updating} = undef;
#
#	odd behavior (maybe Resize timing issue):
#	we occasionally end up with an undef entry at the tail
#
	pop @$clients
		unless (($listsz - 1) == $#$clients);
	return 1;
}
#
#	compute the tabbing traversal order
#	note an anomaly:
#	if the top row doesn't fill the frame, and a top
#	row button is tabbed to, it is automatically moved
#	to the 0,0, and its tab order it recomputed. This
#	means that its impossible to tab to any tab
#	in the top row except the first tab. We may eventually
#	change TabRaise to bring the entire top row down
#	if a top row tab is raised.
#
sub TabOrder {
	my ($this) = @_;
	
	my $rows = $this->{RowList};
	my $clients = $this->{ClientList};
	my ($prev, $next);
	
	foreach my $i (0..$#$rows) {
		my $row = $rows->[$i];
		foreach my $j (0..$#$row) {
			if ($j == 0) {
				$prev = ($i == 0) ? $rows->[-1]->[-1] : $rows->[$i-1]->[-1];
				$next = ($#$row == 0) ? 
					($i == $#$rows) ? $rows->[0]->[0] : $rows->[$i+1]->[0] :
					$row->[$j+1];
			}
			elsif ($j == $#$row) {
				$prev = $row->[$j-1];
				$next = ($i == $#$rows) ? $rows->[0]->[0] : $rows->[$i+1]->[0];
			}
			else {
				$prev = $row->[$j-1];
				$next = $row->[$j+1];
			}

			my $widget = $clients->[$row->[$j]]->[0];
			my $button = $clients->[$row->[$j]]->[5]->Subwidget('Button');
			my $prevwgt = $clients->[$prev]->[0];
			my $prevbtn = $clients->[$prev]->[5]->Subwidget('Button');
			my $nextwgt = $clients->[$next]->[0];
			my $nextbtn = $clients->[$next]->[5]->Subwidget('Button');

			# bind us
	        $button->bind ('<Shift-Tab>', sub {$prevbtn->focus();});
	        $button->bind ('<Left>', sub {$this->TabRaise($prevwgt);});
	        $button->bind ('<Tab>', sub {$nextbtn->focus();});
	        $button->bind ('<Right>', sub {$this->TabRaise($nextwgt);});
		}
	}
	return 1;
}
	
sub current
   {
    shift->TabCurrent (@_);
   }

sub add
   {
    my ($this, %args) = @_;
    return $this->TabCreate
       (
        delete $args{'-caption'},
        delete $args{'-tabcolor'},
       );
   }

sub raised
   {
    shift->TabCurrent (@_);
   }
#
#	return caption of current raised widget
#
sub raised_name {
	my ($this) = @_;

	return undef unless $this->{Raised};
	my $clients = $this->{ClientList};
	foreach my $client (@$clients) {
		return $client->[1]
			if ($client->[0] eq $this->{Raised});
	}
    return undef;
}

sub font
   {
    shift->Font (@_);
   }
#
#	programatically raise a tab using its caption
#
sub raise {
	my ($this, $Caption) = @_;
	return undef unless defined($this->{ClientHash}->{$Caption});
    return $this->TabRaise($this->{ClientList}->[$this->{ClientHash}->{$Caption}]->[0]);
}
#
#	programatically remove a tab using its caption
#
sub delete {
	my ($this, $Caption) = @_;
	return undef unless defined($this->{ClientHash}->{$Caption});
	return $this->TabRemove($Caption);
}
#
#	return a hash of our tabs keyed by caption, so the
#	app can e.g., attach a Balloon to them
#
sub tabs {
	my ($this) = @_;
	my $tabs = { };
	my $clients = $this->{ClientList};
	foreach my $tab (keys %{$this->{ClientHash}}) {
		$tabs->{$tab} = $clients->[$this->{ClientHash}->{$tab}]->[5];
	}
	return $tabs;
}

1;


__END__

=cut

=head1 NAME

Tk::DynaTabFrame - An alternative to the NoteBook widget : a tabbed geometry manager
	with dynamically stacking tabs (yeah!)

=head1 SYNOPSIS

    use Tk::DynaTabFrame;

    $TabbedFrame = $widget->DynaTabFrame
       (
        -font => '-adobe-times-medium-r-normal--20-*-*-*-*-*-*-*',
        -tabcurve => 2,
        -padx => 5,
        -pady => 5,
        -raisecmd => \&raise_callback
        -tablock => undef
        [normal frame options...],
       );

    font     - font for tabs
    tabcurve - curve to use for top corners of tabs
    padx     - padding on either side of children
    pady     - padding above and below children
    raisecmd - code ref invoked on a raise event; passes
    	the caption of the raised tab
	tablock  - locks the resize of the tabs; when set to a true
		value, the tabs will not be rearranged when the enclosing 
		window is resized; default off (ie, tabs are rearranged
		on resize)

    $CurrentSelection = $Window->cget ('-current');
    $CurrentSelection = $Window->cget ('-raised');
    $CurrentCaption = $Window->cget ('-raised_name');

    current  - (Readonly) currently selected widget
    raised   - (Readonly) currently selected widget
    raised_name   - (Readonly) caption of currently selected widget
    
    $Tabs = $Window->cget ('-tabs');
    
    $Tabs - a hashref of the tab Button widgets,
    	keyed by the associated caption. Useful for
    	e.g., attaching balloons to the tabs

    $frame = $TabbedFrame->add
       (
        -caption => 'Tab label',
        -tabcolor => 'yellow',
       );

    caption  - label text for the widget's tab
    tabcolor - background for the tab button
    
    Returns a new Frame widget to be populated by the application.
    
    $TabbedFrame->delete($caption);
    
    Deletes the tab/frame specified by $caption (if it exists).
    
    $TabbedFrame->raise($caption):
    
    Raises the tab/frame specified by $caption (if it exists).

Values shown above are defaults.

=head1 DESCRIPTION

[ NOTE: This module is derived directly from Tk::TabFrame...
	tho you probably can't tell it anymore ]

A Notebook with dynamically rearranging tabs. When you resize
a window, the tabs will either stack or unstack as needed to
fit the enclosing widget's width. Likewise, when tabs are added
or removed, the tabs will stack/unstack as needed.

Tabs are added  at the bottom row, left side, and automatically
become the "raised" tab upon being added. The tabs can be
raised by both mouse clicking, or by using left and right 
keyboard arrows to traverse the tabbing order. If a tab
in a row other than the bottom row is raised, all rows are rotated
down, with bottom rows wrapping back to the top, until
the raised row is moved to the bottom row.

NOTE: As of V. 0.02, unfilled top rows no longer cause
all tabs to rearrange when the top row is raised. However,
removing or adding a tab, or resizing the enclosing widget
with -tablock turned off, *does* cause tab rearrangement.

=head1 CAVEATS

As of v 0.02, this widget may be appropriate 
for configuration dialogs, as the tab movement
is no longer chaotic, assuming no tab removals/additions
occur, and -tablock is turned on, after the initial 
dialog setup is complete.

Other corrections for Ver. 0.02 include improved tabbing order
via the keyboard so it is possible to completely traverse
tabs, eliminating the flickering effect when
adding/raising/deleteing tabs, and use of default platform/
application fonts when none is explicitly defined.

Use with *optional* horizontal scrolled frames (ie, 'os')
seems to cause some race conditions (Config events keep 
resizing the frame up, then down). Use mandatory scrollbars
if you need horiztonals.

=head1 AUTHORS

Dean Arnold, darnold@presicient.com

=head1 HISTORY 

January 16, 2004   : Ver. 0.06
	- fixed programmatic raise
	- added (simple) install test 
	- added programmatic raise button to demo app

January 13, 2004   : Ver. 0.05
	- added "pseudo-tabs" to backfill the space
	between the right side of last tab in a row,
	and the right side of the enclosing frame

January 6, 2004   : Ver. 0.04
	- fixed TabRemove for remove from arbitrary position
	- updated demo app to exersize arbitrary position
	removal
	- fixed apparent timing issue with TabRemove and
	resizing that caused occasional phantom client entries

January 5, 2004   : Ver. 0.03
	- added raised_name() method/-raised_name property
		to return caption of currently raised page
	- fixed tab ordering on resize when raised tab
		gets moved to other than bottom row

December 29, 2003 : Ver. 0.02
	- improve raise behavior
	- improve tab font behavior 
		(use platform/application default when none specified)
	- added tablock option

December 25, 2003 :	Converted from Tk::TabFrame

=cut
