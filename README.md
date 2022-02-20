# croncal
Utility to convert a crontab file to a list of actual events within a date range

### The problem

A crontab file containing hundreds of entries which execute jobs at many different times, and we want to know what runs when, or, perhaps more interestingly, what _will run_ when. All displayed in a calendar-like format, so we can see that on day X, job Y will run at 9:30 and job Z will run at 00:00, 06:00, 12:00 and 18:00 (for example).  
Obviously, "manually" extracting this information by looking at the crontab file itself is going to be an exercise in frustration if there are more than a handful entries (and even then, depending on how they are defined, it would probably require some messing around).

We'd like to have some program that takes a time range (start and end date or start date and duration) and a crontab file to read, and automagically produces the calendar output for the given period. Example follows to better illustrate the concept.

```
# Sample crontab file for this example

# runs at 5:00 every day
0 5 * * * job1

# runs at 00:00 every day
@daily job2

# runs every 7 hours every day, between 7 and 17, that is at 07:00 and 14:00
0 7-17/7 * * * job3

# runs at 17:30 on day 10 of each month
30 17 10 * * job4
```

We want to see the job timeline for the time range between **`2012-06-09 00:00`** and **`2012-06-12 00:00`**. So we run it thus:

<pre>
<b>$ croncal.pl -s '2012-06-09 00:00' -e '2012-06-12 00:00' -f /path/to/crontab</b>
2012-06-09 00:00|job2
2012-06-09 05:00|job1
2012-06-09 07:00|job3
2012-06-09 14:00|job3
2012-06-10 00:00|job2
2012-06-10 05:00|job1
2012-06-10 07:00|job3
2012-06-10 14:00|job3
2012-06-10 17:30|job4
2012-06-11 00:00|job2
2012-06-11 05:00|job1
2012-06-11 07:00|job3
2012-06-11 14:00|job3
</pre>

That's basically the idea of the program. To use a different timezone, just set the `TZ` environment variable before running the code, eg `TZ=America/New_York croncal.pl <options>...`.

Running it with **`-h`** will print a summary of the options it accepts. Output can be in **icalendar** format (so the timeline can be visually seen with any calendar application), plain as above, or we can just print how many jobs would run at each time. When using the plain or icalendar formats, mostly as a debugging aid, it's possible to print the job scheduling spec as was originally found in the crontab file. This is done with the **`-x`** switch, example follows:

<pre>
<b>$ croncal.pl -s '2012-06-09 00:00' -e '2012-06-12 00:00' -f /path/to/crontab -x</b>
2012-06-09 00:00|@daily|job2
2012-06-09 05:00|0 5 * * *|job1
2012-06-09 07:00|0 7-17/7 * * *|job3
2012-06-09 14:00|0 7-17/7 * * *|job3
2012-06-10 00:00|@daily|job2
2012-06-10 05:00|0 5 * * *|job1
2012-06-10 07:00|0 7-17/7 * * *|job3
2012-06-10 14:00|0 7-17/7 * * *|job3
2012-06-10 17:30|30 17 10 * *|job4
2012-06-11 00:00|@daily|job2
2012-06-11 05:00|0 5 * * *|job1
2012-06-11 07:00|0 7-17/7 * * *|job3
2012-06-11 14:00|0 7-17/7 * * *|job3
</pre>

This should help confirm that the job should indeed run at the time shown in the first column (or not: there may be bugs!). Since the program reads from standard input if an explicit filename is not specified, it's possible to output the timeline resulting from multiple crontab files, for example by doing

```
cat crontab1 crontab2 crontabN | croncal.pl [ options ]
```

Ok, semi-UUOC but I was too lazy to implement multiple **`-f`** options.

Final words of caution:

* If you run the program over a long period of time and have cron jobs that run very often, like **`* * * * *`** or similar, that will produce **_a lot_** of output.
* The program was written as a quick and dirty way to solve a specific need, "works for me", is not optimized and does not try to be particularly smart of flexible. It may not be exactly what you were looking for, or may not do what you want, or in the way you want. That's life. Hopefully, it may still be useful to someone.

### Testing

To test, you need to install [shellspec](https://github.com/shellspec). With that installed, just run `./run_tests.sh` and all tests should pass.

To write new tests (please submit so we can add them!), have a look at the `tests/` directory, each file represents a test and contains three blocks (separated by `---`), in this order: start/end timestamp (two lines), input crontab (variable length), expected output (variable length). To create new tests, just add new files in there with the same format.
