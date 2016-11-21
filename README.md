# wspwn
wspwn - Website benchmarking tool

WSPWN is a perl program allowing you to benchmark a website's performances by progressively increasing the number of parallel queries.

At the moment, it is only a wrapper for the benchmarking tool '[weighttp](https://redmine.lighttpd.net/projects/weighttp/wiki)'. It launches weighttp repeatedly, each time increasing the number of requests and concurrent clients.

It then parses the output of weighttp and format it in TSV for all the different measures.

Most options are based on [weighttp](https://redmine.lighttpd.net/projects/weighttp/wiki) options.

I was frustrated with other similar tools that wouldn't do exactly what I wanted, so I decided to make my own.

This is only an evening project; many things could be added, improved or refined, which I will do if I have the need and find the time. Feel free to contribute.

## Prerequisites

1. [weighttp](https://redmine.lighttpd.net/projects/weighttp/wiki)
2. Perl (a decently recent version), no perl packages are necessary (based on the default perl install that ships with Debian)

## Installing

You just need the file ```wspwn.pl```. Then set it as executable and run it (```chmod +x wspwn.pl ; ./wspwn.pl```)

## Usage

See ```./wspwn.pl -h``` for the help.

Example: ```./wspwn.pl -n50 -c0c100 -t4 -i10 -kpg -o "output.tsv" http://127.0.0.1/```

## What's different

Why use this tool?

* It gives you the precise number of errors and their kind, for each consecutive run

* Precise timing: total as well as average time per request

* The ```--request-per-client``` option, which increase the reliability of the test. For instance, if you want to do a test starting from 1 client to 2000, doing 2000 requests each time, then at the end, the clients are only going to execute 1 single request before stopping. In my tests, this doesn't really give reliable results.
  
  So if you want to make sure the clients do at least 10 requests each, you just have to benchmark with 20000 requests. That's all good and fun, but the first steps of the test are going to take forever (1 client doing all the 20k requests by itself).
  
  To fix this issue, the ```--request-per-client``` option tells the clients to always do the specified number of queries. So for our example: 0 to 2000 clients, doing at least 10 requests, the options would be set as follow: ```-n10 --request-per-client -c0c2000```. This way, the first client will do 10 requests, then at the end, 2k clients will issue 20k requests, 10 each.

## Modifiyng

This program is entirely based on weighttp output, though it could be adapted to support any other tool.
The actual parsing of the weighttp output is done inside [```sub format_wh_output { ... }```](wspwn.pl#L142).

It's the only place that depends on weighttp (other than wrapper subs used to invoke weighttp with the correct options [```get_wh_location```](wspwn.pl#L105)/[```invoke_weighttp```](invoke_weighttp)).

## Example output

![Demo results](example-result.png?raw=true)
