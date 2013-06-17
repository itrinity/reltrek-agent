#!/usr/bin/perl


# PERL MODULE WE WILL BE USING
use Getopt::Std;
use Time::HiRes qw(gettimeofday);
use POSIX qw(setsid);
use POSIX qw(strftime);
use LWP::UserAgent;

if($ARGV[0] eq "start") {
    start();
}
elsif($ARGV[0] eq "stop") {
    stop();
    exit 1;
}
elsif($ARGV[0] eq "restart") {
    stop();
    start();
}
elsif($ARGV[0] eq "status") {
    status();
}

sub start {
    if (-e '/var/run/reltrek/reltrek.pid') {
        print "Reltrek is already running. Try restart.\n";
        exit 1;
    }

    print "Starting...\n";

    # demonize
    chdir '/';
    umask 0;
    open STDIN,  '/dev/null'   or die "Can't read /dev/null: $!";
    open STDOUT, '>>/dev/null' or die "Can't write to /dev/null: $!";
    open STDERR, '>>/dev/null' or die "Can't write to /dev/null: $!";
    defined( my $pid = fork ) or die "Can't fork: $!";
    exit if $pid;

    open (PIDFILE, '>', '/var/run/reltrek/reltrek.pid');
    #print PIDFILE $$;
    close (PIDFILE); 
}

sub stop {
    my $fh;
    unless ( open( $fh, '<',  '/var/run/reltrek/reltrek.pid') ) {
        return;
    }

    my $pid = <$fh>;
    close($fh);

    unlink '/var/run/reltrek/reltrek.pid';

    chomp($pid);

    # XXX Isn't it too simple?
    kill( HUP => $pid );    
    print "Stopped...\n";
}

sub status {
    if (-e '/var/run/reltrek/reltrek.pid') {
        print "Reltrek is running...";      
    }
    else {
        print "Reltrek is stopped";
    }

    exit 1;

}

my $ua = new LWP::UserAgent;
$ua->timeout(15);
$ua->agent('Mozilla/5.0');

$iteration = 0;
$cputime = 1;
@proc_row = ();
$rx = -1; $tx = -1;
$swap_read = $swap_write = -1;
$cpu_user = $cpu_nice = $cpu_sys = $cpu_wait = $cpu_idle = -1;



#  Loading config file
my $conf = {};



            if ( open( my $fh, '<', "/etc/reltrek/agent.conf" ) ) {
                for (<$fh>) {
                    next if /^\s*(?:\#|$)/;
                    if (/^\s*([^=]+?)\s*=\s*"?(.*?)"?\s*$/) {
                        $$conf{$1} = $2;
                    }
                }
            }
            elsif ( $! == POSIX::ENOENT ) {
                print "File does not exist";
            }
            else {
                print "open(): $!";
            }


print $conf->{SERVER_ID};


while(true) {  
  	#	CPU Utilization
	$cpu = `cat /proc/stat`;
	
	$startIndex = 0;
	$endIndex = 0;
	
	$work_a = $work_b = $total_a = $total_b = 0;
	
	$startIndex = index($cpu, "cpu", $endIndex);
	$startIndex = index($cpu, " ", $startIndex) + 2;
	$endIndex = index($cpu, "\n", $startIndex);
	$row = substr($cpu, $startIndex, $endIndex - $startIndex);
	    
	@col = split(/ {1,}/, $row);
	    
	$cu = @col[0] * 1;
	$cn = @col[1] * 1;
	$cs = @col[2] * 1;
	$cw = @col[4] * 1;
	$ci = @col[0] * 1 + @col[1] * 1 + @col[2] * 1 + @col[3] * 1 + @col[4] * 1;	   


	if($cpu_user != -1) {
	    @cpu = ($cu - $cpu_user, $cs - $cpu_sys, $cw - $cpu_wait, $ci - $cpu_idle);
	    $cputime = $ci - $cpu_idle;
	}
	else {
		@cpu = (0, 0, 0, 0);
	}
	    
	$cpu_user = $cu;
	$cpu_nice = $cn;
	$cpu_sys = $cs;
	$cpu_wait = $cw;
	$cpu_idle = $ci;

  #$cputime = $ci;
  #$cputime = $cpu - $cputime;
  

  @proc = ();

  $top = `top -b -n 1`;
  my $out = '';
    
  $rows = 1; $start = 0; $endIndex = 0;
  while(($endIndex = index($top, "\n", $endIndex)) != -1) {
    $endIndex += 1;
    
    if($rows > 6) { 
      $row = substr($top, $start, $endIndex - $start);
      @col = split(/ {1,}/, $row);
      
       
      if(@col[0] eq '') {
        shift(@col);
      }

                  

        if(-d "/proc/@col[0]") {
          @colproc = split(/ {1,}/, `cat /proc/@col[0]/stat`);
          $procTime = @colproc[13] + @colproc[14];
        }
        else {
          $procTime = 0;
        }        
        
        # Edit or update new proc
        $new_proc = 1;
 
        for($i = 0; $i < scalar(@proc_row); $i++) {
          if(($proc_row[$i][0] == @col[0])) {
            $proc_row[$i][3] = ($procTime - $proc_row[$i][5]) * 100 / $cputime;         
            $proc_row[$i][4] = @col[9] * 1;
            $proc_row[$i][5] = $procTime;
            $proc_row[$i][6] = $iteration;
            
            $new_proc = 0;
            last;
          }
        }
   
        if($new_proc == 1) {
          push @proc_row, [(@col[0], @col[1], @col[11], 0, $col[9], $procTime, $iteration)];                
        }

    }    
    $start = $endIndex;
    $rows++;
  }
  
  for($i = 0; $i < scalar(@proc_row); $i++) {
    if(($proc_row[$i][4] > 0 || $proc_row[$i][5] > 0) && $proc_row[$i][6] > 0 && $proc_row[$i][6] == $iteration) {
      $updated = 0;
      
      for($j = 0; $j < scalar(@proc); $j++) {
        if($proc_row[$i][1] eq $proc[$j][0] && $proc_row[$i][2] eq $proc[$j][1]) {
          $proc[$j][2] = $proc[$j][2] + 1;
          $proc[$j][3]  = $proc[$j][3] + $proc_row[$i][4];
          $proc[$j][4]  = $proc[$j][4] + $proc_row[$i][3];
          
          $updated = 1;
        }
      }
      
      if($updated == 0) {
        push @proc, [($proc_row[$i][1], $proc_row[$i][2], 1, $proc_row[$i][4], $proc_row[$i][3])];
      }
    }
    elsif($proc_row[$i][6] < $iteration) {
      splice(@proc_row, $i);
    }
  }

  $uptime = `uptime`;
  $startIndex = index($uptime, 'load average: ', 0) + 14;
  $endIndex = index($uptime, ',',  $startIndex);
  $load = substr($uptime, $startIndex, $endIndex - $startIndex);
  
  
  @mem = ();
  $out = `cat /proc/meminfo`;

  $start = 0; $endIndex = 0;
  while(($endIndex = index($out, "\n", $endIndex)) != -1) {
    $endIndex += 1;

    $row = substr($out, $start, $endIndex - $start);
    
    @col = split(/ {1,}/, $row);

    if(@col[0] eq 'MemTotal:') {
      push(@mem, @col[1]);
    }
    elsif(@col[0] eq 'MemFree:') {
      push(@mem, @col[1]);
    }
    elsif(@col[0] eq 'Buffers:') {
      push(@mem, @col[1]);
    }
    elsif(@col[0] eq 'Cached:') {
      push(@mem, @col[1]);
    }
    elsif(@col[0] eq 'SwapTotal:') {
      push(@mem, @col[1]);
    }
    elsif(@col[0] eq 'SwapFree:') {
      push(@mem, @col[1]);
    }
    
    $start = $endIndex;
  }
  
  
  @disk = ();
  $out = `df`;

  $volumeName = "";
  $rows = 1; $start = 0; $endIndex = 0;
  while(($endIndex = index($out, "\n", $endIndex)) != -1) {
    $endIndex += 1;
    
    if($rows > 1) {
      $row = substr($out, $start, $endIndex - $start);
      
      @col = split(/ {1,}/, $row);
      
      #	There is only volume name - multiple lines
      if(scalar(@col) == 1) {
	    $volumeName = @col[0];
	    $volumeName =~ s/^\s+|\s+$//g; 
      }
      else { 
      	if(length($volumeName) > 0) {
	    	@col[0] = $volumeName;
	    	$volumeName = "";  
      	} 
      	push(@disk, [(@col[0], substr(@col[4], 0, length(@col[4]) - 1))]);
      }
    }
    $start = $endIndex;
    $rows++;
  }
  
  
  @net = ();  
  $out = `cat /proc/net/dev`;

  $rows = 1; $start = 0; $endIndex = 0; 
  $rx_now = $tx_now = $rp_now = $tp_now = $re_now = $te_now = 0;

  while(($endIndex = index($out, "\n", $endIndex)) != -1) {
    $endIndex += 1;
    
    if($rows > 1) {
      $row = substr($out, $start, $endIndex - $start);
      
      if(index($row, 'eth', 0) != -1) {
        @col = split(/ {1,}/, substr($row, index($row, ":") + 1));   
        
        $rx_now += @col[0];
        $tx_now += @col[8];
        $rp_now += @col[1];
        $tp_now += @col[9];
        $re_now += @col[2];
        $te_now += @col[10];
      }
    }
    $start = $endIndex;
    $rows++;
  } 
    
  if($rx != -1) {
	  @net = (sprintf("%.2f", ($rx_now - $rx)/61440), sprintf("%.2f", ($tx_now - $tx)/61440), $rx_now, $tx_now, $rp_now - $rp, $tp_now - $tp, $re_now - $re, $te_now - $te);        
  }
  else {
	  @net = (0, 0);
  }
        
  $rx = $rx_now;
  $tx = $tx_now;
  $rp = $rp_now;
  $tp = $tp_now;
  $re = $re_now;
  $te = $te_now; 


  
  
  @iostat = ();  
  $out = `iostat -d -x 1 2`;

  $rows = 1; $start = 0; $endIndex = 0; $round = 0;
  while(($endIndex = index($out, "\n", $endIndex)) != -1) {
    $endIndex += 1;
    
    $row = substr($out, $start, $endIndex - $start - 1);
    
    if(index($row, "Device:") != -1) {
	   $round += 1; 
    }
    elsif($round >= 2 ) {
       @col = split(/ {1,}/, $row); 
       
       if(scalar(@col) > 1) { 
       		push(@iostat, [(@col[0], sprintf("%.2f", @col[1]), sprintf("%.2f", @col[2]), sprintf("%.2f", @col[3]), sprintf("%.2f", @col[4]), sprintf("%.2f", @col[5]), sprintf("%.2f", @col[6]), sprintf("%.2f", @col[7]), sprintf("%.2f", @col[8]), sprintf("%.2f", @col[9]), sprintf("%.2f", @col[10]), sprintf("%.2f", @col[11]))]); 
       }
    }
    $start = $endIndex;
    $rows++;
  }
  
  
  
  @swap = ();  
  $out = `cat /proc/vmstat`;

  $swap_read_now = $swap_write_now = 0;

  $start = 0; $endIndex = 0;
  while(($endIndex = index($out, "\n", $endIndex)) != -1) {
    $endIndex += 1;

    $row = substr($out, $start, $endIndex - $start);
    
    @col = split(/ {1,}/, $row);

    if(@col[0] eq 'pswpin') {
      $swap_read_now = @col[1];
    }
    elsif(@col[0] eq 'pswpout') {
      $swap_write_now = @col[1];
    }
    
    $start = $endIndex;
  }
    
  if($swap_read != -1) {
	  @swap = (($swap_read_now - $swap_read), ($swap_write_now - $swap_write));        
  }
  else {
	  @swap = (0, 0);
  }
        
  $swap_read = $swap_read_now;
  $swap_write = $swap_write_now;
  
  

    
  @data = ();
  push(@data, [@cpu]);
  push(@data, [$load]);
  push(@data, [@mem]);
  push(@data, [@disk]);
  push(@data, [@net]);
  push(@data, [@proc]);
  push(@data, [@iostat]);
  push(@data, [@swap]);

  sub is_array {
    my ($ref) = @_;
    # Firstly arrays need to be references, throw
    #  out non-references early.
    return 0 unless ref $ref;
  
    # Now try and eval a bit of code to treat the
    #  reference as an array.  If it complains
    #  in the 'Not an ARRAY reference' then we're
    #  sure it's not an array, otherwise it was.
    eval {
      my $a = @$ref;
    };
    if ($@=~/^Not an ARRAY reference/) {
      return 0;
    } elsif ($@) {
      die "Unexpected error in eval: $@\n";
    } else {
      return 1;
    }
  
  }

$json = '[';

for my $i (0..$#data) {
   
  if($i > 0) {
     $json .= ',';
  }
  
  
  if($#{$data[$i]} > 0) { 
    $json .= '[';
     
     for my $j (0..$#{$data[$i]}) {   
               
        if($j > 0) {
          $json .= ',';
        }
            
        if($#{$data[$i][$j]} > 0) {
          $json .= '[';
          
          for my $k (0..$#{$data[$i][$j]}) { 
            if($k > 0) {
              $json .= ',';
            }
            $json .= '"' . $data[$i][$j][$k] . '"';
          }
          
          $json .= ']';
        }
        else {
          $json .= '"' . $data[$i][$j] . '"';
        }   
     }
     
     $json .= ']';
   }
   else {
    $json .= '["' . $data[$i][0] . '"]';
   }
   
   
}
$json .= ']';

  
  #print jsonizer ([@data]);

    
  #$json = JSON->new->allow_nonref;
  #$o = $json->encode([@data]);
  #print 'http://88.86.117.129:88/?server=' . $conf->{SERVER_ID} . '&data=' . $json;
  $ua->get('http://88.86.117.129:88/?server=' . $conf->{SERVER_ID} . '&data=' . $json);
  
  $iteration = $iteration + 1;
  sleep(60);
}
