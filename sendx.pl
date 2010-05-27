#!/usr/bin/env perl

use strict;
use Getopt::Long;
use MIME::Entity;
use Net::SMTP;
use File::Temp qw(tempfile);
use IO::File;

my $smtp_class = 'Net::SMTP';
my $debug;
my $verbose;
my $help;
my $subject;
my $from;
my @to;
my @cc;
my @bcc;
my @attach;
my $data;
my $host;
my $user;
my $pass;
my $ssl;
my $num = 1;
my $max;
my %ext;

GetOptions(
  "debug+"      => \$debug,
  "verbose+"    => \$verbose,
  "help+"       => \$help,
  "h|host=s"    => \$host,
  "user=s"      => \$user,
  "pass=s"      => \$pass,
  "S|ssl+"      => \$ssl,
  "from=s"      => \$from,
  "to=s"        => \@to,
  "cc=s"        => \@cc,
  "bcc=s"       => \@bcc,
  "s|subject=s" => \$subject,
  "attach=s"    => \@attach,
  "data=s"      => \$data,
  "num=i"       => \$num,
  "max=i"       => \$max,
  "ext=s"       => \%ext
);

if ($help) {
print <<'EOF';
  ./sendx.pl [option]
    
Basic Options:
    -d, --debug       debug mode.   (no send)
    -v, --verbose     verbose mode.
        --help        usage.
    
SMTP Options:
    -h, --host        smtp host
    -u, --user        auth user
    -p, --pass        auth pass
    -S, --ssl         use ssl
    
Mail Options:
    -f, --from        From Address   (Envelope And Header)
    -t, --to          To Address     (Envelope And Header)
    -c, --cc          Cc Address     (Envelope And Header)
    -b, --bcc         Bcc Address    (Envelope)
    -s, --subject     Subject Header
    -a, --attach      Attach File    (file path)
    -d, --data        Data
    -e, --ext         ExtOption      (Encoding/Header ...etc)
    
Performance Options:
    -n, --num         TotalSendMails
    -m, --max         MaxProcess

ext.

Simple:
    ./sendx.pl -h 10.0.0.10 -f s-aska@example.jp -t foo@example.jp -s test001

FullOption:
    ./send.pl -h 10.0.0.10:465 -S \
              -u s-aska@example.jp \
              -p password \
              -f s-aska@example.jp \
              -t test1@example.jp \
              -c test2@example.jp \
              -c test3@example.jp \
              -b test4@example.jp \
              -s test001 \
              -a /tmp/maillog \
              -a /tmp/maillog.1 \
              -a /tmp/maillog.2 \
              -d hello_world \
              -e X-Mailer=HyperSned.pl \
              -e X-Password=password00 \
              -e X-Spam=spam \
              -e Encoding=Base64
              -n 10 -m 2

FormatString:
    ./sendx.pl -h 10.0.0.10 -f test-%04d@example.jp -t test-%04d@example.jp -s test-%04d

EOF
exit(0);
}

if (-f $data) {
  open my $fh, $data;
  $data = join '', <$fh>;
  close $fh;
}

my $top = MIME::Entity->build(From    => $from,
                              To      => join(',', @to),
                              Cc      => join(',', @cc),
                              Subject => $subject,
                              Data    => [$data || $subject],
                              %ext);

$top->attach(Path => $_, Encoding => "base64", Type => "application/octet-stream") for @attach;


if ($debug) {
  print "use_ssl: $ssl\n";
  $top->print(\*STDOUT);
  exit(0);
}

my ($fh, $filename) = tempfile( UNLINK => 0 );
&verbose('tempfile: %s', $filename);
$top->print($fh);
$fh->close;

if ($max > 1) {
  &verbose('parallel mode.');
  
  eval qq{use Parallel::ForkManager;};
  my $pm_class = 'Parallel::ForkManager';
  
  my $pm = $pm_class->new($max);
  
  my $b = time;
  &verbose('%s begin.', &now);
  
  foreach my $i (1..$num) {
    my $pid = $pm->start and next;
    my $b   = time;
    &verbose('[%s] %s begin.', $i, &now);
    &smtpsend($i);
    &verbose('[%s] %s end  %s sec.', $i, &now, (time - $b));
    $pm->finish;
  }
  
  $pm->wait_all_children;
  
  &verbose('%s finish  %s sec  %s mails/sec.', &now, (time - $b), ($num / ((time - $b) || 1)));
  
} else {
  &verbose('cereal mode.');
  my $b   = time;
  &verbose('[%s] begin.', &now);
  for ( 1..$num ) {
    &smtpsend($_);
  }
  &verbose('[%s] end  %s sec.', &now, (time - $b));
}

unlink($filename);

sub smtpsend {
  my $cnt = shift;
  
  $fh = new IO::File $filename;
  
  if ($ssl) {
    eval qq{use Net::SMTP::SSL;};
    $smtp_class = 'Net::SMTP::SSL';
  }
  
  my $smtp = $smtp_class->new($host, Timeout => 120, Debug => 0) || die $!;
  
  eval {
    $smtp->auth($user, $pass) || die  'AUTH: ' . $! . ', ' . $smtp->code().': '.$smtp->message()
      if $user and $pass;
    $smtp->mail($from)        || die  'MAIL: ' . $! . ', ' . $smtp->code().': '.$smtp->message();
    $smtp->to($_)             || die  'RCPT: ' . $! . ', ' . $smtp->code().': '.$smtp->message()
      for (@to, @cc, @bcc);
    $smtp->data()             || die  'DATA: ' . $! . ', ' . $smtp->code().': '.$smtp->message();
    my $buf;
    while (read($fh, $buf, 4096)) {
      $smtp->datasend($buf)   || die  'SEND: ' . $! . ', ' . $smtp->code().': '.$smtp->message();
    }
    $smtp->dataend()          || warn 'DEND: ' . $! . ', ' . $smtp->code().': '.$smtp->message();
    $smtp->quit()             || die  'QUIT: ' . $! . ', ' . $smtp->code().': '.$smtp->message();
    &verbose("ok $cnt");
  };if($@) {
    $smtp->quit()             || die  'QUIT: ' . $! . ', ' . $smtp->code().': '.$smtp->message();
    die $@;
  }
}

sub verbose {
  my ($ptn, @args) = @_;
  printf $ptn, @args;
  print "\n";
}

sub now {
  my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);

  return sprintf "%02d:%02d:%02d", $hour, $min, $sec;
}

exit;
