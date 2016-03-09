#!/usr/bin/perl

# simple crontab calandar generator

# CopyrightCopyright  Davide Brini, 07/07/2012
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.

use warnings;
use strict;

use Time::Local;
use Getopt::Std;

my @monthmap = ( 'january|jan', 'february|feb', 'march|mar', 'april|apr', 'may', 'june|jun', 'july|jul', 'august|aug', 'september|sep', 'october|oct', 'november|nov', 'december|dec' );
my @dowmap = ( 'sunday|sun', 'monday|mon', 'tuesday|tue', 'wednesday|wed', 'thursday|thu', 'friday|fri', 'saturday|sat' );

my $progname = "croncal.pl";
my %opts;


# default values

# 1 day from now by default
my $startsec = int(time / 60) * 60;
my $endsec;
my $duration = 86400;

my $outformat = 'plain';
my $xtrainfo = 0;

my $plainformat = "%04d-%02d-%02d %02d:%02d%.0s|%s\n";

my %calendar = ();


getopts('s:e:d:f:o:xh', \%opts);

if (exists($opts{h})) {
  show_help();
  exit 1;
}

if (exists($opts{e}) and exists($opts{d})) {
  print STDERR "Can't use -e and -d together\n";
  show_help();
  exit 1;
}

if (exists($opts{s})) {

  my $secs = parsedate($opts{s});

  if ($secs == 0) {
    print STDERR "Invalid start date $opts{s}, terminating\n";
    show_help();
    exit 1;
  } else {
    $startsec = ($secs / 60) * 60;
  }
}

if (exists($opts{d})) {
  $duration = $opts{d};
}

if (exists($opts{e})) {
  my $secs = parsedate($opts{e});

  if ($secs == 0) {
    print STDERR "Invalid end date $opts{e}, terminating\n";
    show_help();
    exit 1;
  } else {
    $endsec = $secs;
  }
} else {
  $endsec = $startsec + $duration;
}

if (exists($opts{f})) {
  @ARGV = ($opts{f});
}

if (exists($opts{o})) {
  $outformat = $opts{o};
}

if (exists($opts{x}) and $outformat ne 'count') {
  $xtrainfo = 1;
  $plainformat = "%04d-%02d-%02d %02d:%02d|%s|%s\n";
}


if ($outformat ne 'ical' and $outformat ne 'plain' and $outformat ne 'count') {
  print STDERR "Unknown output format $outformat specified, terminating\n";
  exit 1;
}

my @joblist = ();

while (<>) {

  chomp;

  # remove leading/trailing spaces
  s/^\s+//; s/\s+$//;

  # skip comments and emtpy lines
  next if /^($|#)/;

  # skip variable assignments
  next if /^\s*\S+\s*=\s*/;

  my %raw = ();
  my %parsed = ();

  # we must have either:
  # - one field beginning with @ + command
  # - five fields + command

  if (/^(@(reboot|yearly|annually|monthly|weekly|daily|hourly))\s+(.*)/i) {

    my $type = $2;
    $parsed{sched_orig} = $1;

    if ($type eq 'yearly' or $type eq 'annually') {
      %raw = ('min' => '0', 'hour' => '0', 'dom' => '1', 'month' => '1', 'dow' => '*', 'command' => $3);
    } elsif ($type eq 'monthly') {
      %raw = ('min' => '0', 'hour' => '0', 'dom' => '1', 'month' => '*', 'dow' => '*', 'command' => $3);
    } elsif ($type eq 'weekly') {
      %raw = ('min' => '0', 'hour' => '0', 'dom' => '*', 'month' => '*', 'dow' => '0', 'command' => $3);
    } elsif ($type eq 'daily') {
      %raw = ('min' => '0', 'hour' => '0', 'dom' => '*', 'month' => '*', 'dow' => '*', 'command' => $3);
    } elsif ($type eq 'hourly') {
      %raw = ('min' => '0', 'hour' => '*', 'dom' => '*', 'month' => '*', 'dow' => '*', 'command' => $3);
    } elsif ($type eq 'reboot') {
      print STDERR "Warning, skipping \@reboot entry at line $.: $_\n";
      next;
    } else {
      print STDERR "Unknown line/cannot happen at line $., skipping: $_\n";
      next;
    }

  } elsif (/^((\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+))\s+(.*)/) {

    $parsed{sched_orig} = $1;

    # regular entry
    %raw = ('min' => $2, 'hour' => $3, 'dom' => $4, 'month' => $5, 'dow' => $6, 'command' => $7);

  } else {
    print STDERR "Warning, skipping unrecognized crontab line $.: $_\n";
    next;
  }

  my $success = 1;

  # if all fields parse OK, save the entry, otherwise skip it
  
  for my $type (qw(min hour dom month dow)) {

    my ($errmsg, @result) = parse($raw{$type}, $type);

    if ($errmsg ne "") {
      print STDERR "Parsing line $.: $errmsg, skipping line\n";
      $success = 0;
      last;
    }

    # silly way to create a hash and remove duplicates
    $parsed{$type} = { map { $_, '' } @result };

    # save original field value
    $parsed{"${type}_orig"} = $raw{$type};
  }

  if ($success) {

    # save the parsed entry

    $parsed{command} = $raw{command};

    push @joblist, \%parsed;
  }
}


# now, check what is due when
for (my $second = $startsec; $second < $endsec; $second += 60) {

  my ($dummy1, $min, $hour, $day, $month, $year, $dow, $dummy2, $dummy3) = localtime($second);

  $month++;
  $year += 1900;

  for my $parsed (@joblist) {

    if (isdue($day, $month, $year, $dow, $hour, $min, $parsed)) {
      push @{$calendar{$year}{$month}{$day}{$hour}{$min}}, $parsed;
    }
  }
}


# Finally, print the resulting calendar

if ($outformat eq 'ical') {
  print "BEGIN:VCALENDAR\n";
  print "VERSION:1.0\n";
}

for my $year (sort { $a <=> $b} keys %calendar) {
  for my $month (sort { $a <=> $b} keys %{$calendar{$year}}) {
    for my $day (sort { $a <=> $b} keys %{$calendar{$year}{$month}}) {
      for my $hour (sort { $a <=> $b} keys %{$calendar{$year}{$month}{$day}}) {
        for my $minute (sort { $a <=> $b} keys %{$calendar{$year}{$month}{$day}{$hour}}) {

          if ($outformat eq 'count') {
            printf $plainformat, $year, $month, $day, $hour, $minute, "", scalar (@{$calendar{$year}{$month}{$day}{$hour}{$minute}});
          } else {

            for my $parsed (@{$calendar{$year}{$month}{$day}{$hour}{$minute}}) {

              my ($sched, $job) = (${$parsed}{sched_orig}, ${$parsed}{command});;

              if ($outformat eq 'ical') {

                print "BEGIN:VEVENT\n";
                printf "DTSTART:%04d%02d%02dT%02d%02d%02d\n", $year, $month, $day, $hour, $minute, "00";
                printf "DTEND:%04d%02d%02dT%02d%02d%02d\n", $year, $month, $day, $hour, $minute, "30";   # fake duration of 30 seconds
                print "SUMMARY:$job\n";
                print "LOCATION:Cron file\n";

                if ($xtrainfo) {
                  print "DESCRIPTION:|$sched|$job\n";
                } else {
                  print "DESCRIPTION:$job\n";
                }

                print "PRIORITY:3\n";
                print "END:VEVENT\n";

              } elsif ($outformat eq 'plain') {

                printf $plainformat, $year, $month, $day, $hour, $minute, $sched, $job;

              } else {

                print STDERR "Unknown output format $outformat - cannot happen!\n";

              }
            }
          }
        }
      }
    }
  }
}

if ($outformat eq 'ical') {
  print "END:VCALENDAR\n";
}

sub show_help {

  print STDERR "Usage: $progname [ -s start ] [ -e end | -d duration ] [ -f cronfile ] [ -o format ] [ -x ]\n";
  print STDERR "       $progname -h\n";
  print STDERR "\n";
  print STDERR "-s start     : start time for the calendar in 'YYYY-MM-DD HH:MM' format (default: now)\n";
  print STDERR "-e end       : end time for the calendar in 'YYYY-MM-DD HH:MM' format (cannot be used with -d), default: now + $duration seconds\n";
  print STDERR "-d duration  : duration IN SECONDS (cannot be used with -e), default: $duration\n";
  print STDERR "-f cronfile  : cron file to read (default: stdin)\n";
  print STDERR "-o format    : output format. Can be 'plain', 'ical' or 'count' (default: plain)\n";
  print STDERR "-x           : adds extra info (scheduling elements from original file). Ignored if output format is 'count'. Default: no extra info\n";
  print STDERR "-h           : show this help\n";
  print STDERR "\n";
  print STDERR "Example: $progname -f /var/spool/cron/user1 -s '2012-07-24 00:00' -d 7200 -o ical\n";

}

#          field          allowed values
#              -----          --------------
#              minute         0-59
#              hour           0-23
#              day of month   1-31
#              month          1-12 (or names, see below)
#              day of week    0-7 (0 or 7 is Sunday, or use names)
#
#       A field may contain an asterisk (*), which always stands for "first-last".
#
#       Ranges of numbers are allowed.  Ranges are two numbers separated with a hyphen.  The specified range is inclusive.  For example, 8-11 for an 'hours' entry specifies  execu‐
#       tion at hours 8, 9, 10, and 11.
#
#       Lists are allowed.  A list is a set of numbers (or ranges) separated by commas.  Examples: "1,2,5,9", "0-4,8-12".
#
#       Step  values can be used in conjunction with ranges.  Following a range with "/<number>" specifies skips of the number's value through the range.  For example, "0-23/2" can
#       be used in the 'hours' field to specify command execution for every other hour (the alternative in the V7 standard is "0,2,4,6,8,10,12,14,16,18,20,22").   Step  values  are
#       also permitted after an asterisk, so if specifying a job to be run every two hours, you can use "*/2".
#
#       Names  can  also  be  used for the 'month' and 'day of week' fields.  Use the first three letters of the particular day or month (case does not matter).  Ranges or lists of
#       names are not allowed.
#
#       Note: The day of a command's execution can be specified in the following two fields — 'day of month', and 'day of week'.  If both fields are restricted (i.e., do  not  con‐
#       tain the "*" character), the command will be run when either field matches the current time.  For example,
#       "30 4 1,15 * 5" would cause a command to be run at 4:30 am on the 1st and 15th of each month, plus every Friday.

# This comment from cron.c explains what happens if *only one of dom and dow is restricted*:
#
# /* the dom/dow situation is odd.  '* * 1,15 * Sun' will run on the
#  * first and fifteenth AND every Sunday;  '* * * * Sun' will run *only*
#  * on Sundays;  '* * 1,15 * *' will run *only* the 1st and 15th.  this
#  * is why we keep 'e->dow_star' and 'e->dom_star'.  yes, it's bizarre.
#  * like many bizarre things, it's the standard.
#  */

#       @reboot    :    Run once after reboot.
#       @yearly    :    Run once a year, ie.  "0 0 1 1 *".
#       @annually  :    Run once a year, ie.  "0 0 1 1 *".
#       @monthly   :    Run once a month, ie. "0 0 1 * *".
#       @weekly    :    Run once a week, ie.  "0 0 * * 0".
#       @daily     :    Run once a day, ie.   "0 0 * * *".
#       @hourly    :    Run once an hour, ie. "0 * * * *".

sub parse {

  my ($field, $type) = (shift, shift);

  my ($min, $max, $desc);

  if ($type eq 'min') {
    ($min, $max, $desc) = (0, 59, 'minutes');
  } elsif ($type eq 'hour') {
    ($min, $max, $desc) = (0, 23, 'hours');
  } elsif ($type eq 'dom') {
    ($min, $max, $desc) = (1, 31, 'day of month');
  } elsif ($type eq 'month') {
    ($min, $max, $desc) = (1, 12, 'month');
  } elsif ($type eq 'dow') {
    ($min, $max, $desc) = (0, 6, 'day of week');    # 0 or 7 is sunday, 7 is silently converted to 0
  } else {
    return "field - $field - of (unrecognized) type $type: cannot happen!", ();
  }

  # expand stars
  $field =~ s/\*/$min-$max/g;

  # replace dow and month names with numbers
  if ($type eq 'month') {
    my $count = 0;
    for my $m (@monthmap) {
      $count++;
      $field =~ s/$m/$count/gi;
    }
  } elsif ($type eq 'dow') {
    my $count = 0;
    for my $d (@dowmap) {
      $field =~ s/$d/$count/gi;
      $count++;
    }
  }

  # At this point it should be a list of items (possibly one), each of which
  # is either a single number, a range (3-7), or a step interval (2-30/4)
  # Ranges and step intervals can be further expanded to lists: 3-7 becomes
  # 3,4,5,6,7 and 2-30/4 becomes 2,6,10,14,18,22,26,30
  # At the end, we have just a long list of values.

  # split on commas

  my @items = split(/,/, $field);

  my @values = ();

  for my $item (@items) {

    if ($item =~ /^\d+$/) {

      # single number

      if ($type eq 'dow' and $item eq '7') {
        $item = '0';
      }

      if ($item >= $min and $item <= $max) {

        # remove leading zeros (but leave a single 0 if there's nothing else)
        $item =~ s/^0+(\d)/$1/;

        push @values, $item;
        next;
      } else {
        return "invalid value $item for field - $field - of type $type", ();
      }
    }

    my $step;

    # see if there is a step, save and remove it
    if ($item =~ m{/(\d+)$}) {
      $step = $1;
      $step =~ s/^0+(\d)/$1/;
      if ($step eq '0') {
        return "step cannot be zero for field - $field - of type $type", ();
      }
      $item =~ s{/(\d+)$}{};
      $item =~ s/^0+(\d)/$1/;

    } elsif ($item =~ m{/}) {
      return "unrecognized step format for field - $field - of type $type", ();
    } else {
      $step = 1;
    }

    if ($step > ($max - $min)) {
      return "too big step value $step for field - $field - of type $type", ();
    }

    # now, expand the range...

    # ...because it's a range, right?
    if ($item =~ /^(\d+)-(\d+)$/) {
      my ($from, $to) = ($1, $2);

      $from =~ s/^0+(\d)/$1/;
      $to =~ s/^0+(\d)/$1/;

      if ($from > $to) {
        return "start value $from greater than end value $to for field - $field - of type $type", ();
      }

      for (my $i = $from; $i <= $to; $i += $step) {
        push @values, $i;
      }

    } else {
      return "invalid range/not a range for field - $field - of type $type", ();
    }

  }

  return "", @values;
}

# given a crontab entry and a date, returns true
# if the task has to be executed
sub isdue {

  my ($day, $month, $year, $dow, $hour, $min, $parsedref) = (shift, shift, shift, shift, shift, shift, shift);

  # we have to run if:

  # $min is included in the min list
  #
  # AND
  #
  # $hour is included in the hour list  
  #
  # AND
  #
  # silly dom/dow logic is true
  #
  # AND
  #
  # $month is included in the month list

  my %parsed = %{$parsedref};

  # yes, if one used 1-31, or 1-6,7-31 or 0-6 or whatever, it's not the
  # same as specifying a real star. It's easy to enhance the code to
  # include those cases, though.

  my ($stardom, $stardow) = ($parsed{dom_orig} eq '*', $parsed{dow_orig} eq '*');

  return (exists($parsed{min}{$min}) and
          exists($parsed{hour}{$hour}) and
          exists($parsed{month}{$month}) and

          # silly dom/dow logic
          
         ( ($stardom and $stardow) or
           (not $stardom and not $stardow and (exists($parsed{dom}{$day}) or exists($parsed{dow}{$dow}))) or
           (not $stardom and exists($parsed{dom}{$day})) or
           (not $stardow and exists($parsed{dow}{$dow})) ));

}

# gets a date in YYYY-MM-DD HH:MM format, returns
# the number of seconds from epoch, or 0 if the date is not valid
sub parsedate {

  my $date = shift;

  my ($year, $month, $day, $hour, $minute);

  if (!(($year, $month, $day, $hour, $minute) = $date =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d)$/)) {
    # invalid date
    return 0;
  }

  # also checks that values are within ranges
  my $secs = timelocal(0, $minute, $hour, $day, $month - 1, $year - 1900);

  return $secs; 

}
