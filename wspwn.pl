#!/usr/bin/perl -w

# wspwn
#
# Copyright (C) 2016 
#
# This file is part of wspwn.
#
# wspwn is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# wspwn is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with WeeChat.  If not, see <http://www.gnu.org/licenses/>.
#

 use strict;
 use warnings;

 use Data::Dumper;
 use Getopt::Long;

my ( $url
   , $nreq
   , $threads
   , @clients
   , $ka
   , $ipv6
   , @headers
   , $wh_location
   , $inc
   , $req_p_c
   , $pt
   , $file
   );

my @file_headers = ();
my $fh;

sub say { print STDOUT @_, "\n"; }
sub err { print STDERR @_, "\n"; }
sub save { print @_, "\n"; }

sub help
{
print <<"EOH";

WSPWN is a perl program allowing you to benchmark a website's performances by progressively increasing the number of parallel queries.
At the moment, it is only a wrapper for the benchmarking tool 'weighttp'. It launches weighttp repeatedly, each time increasing the number of requests and concurrent clients.
It then parses the output of weighttp and format it in TSV for all the different measures.

Most options are based on weighttp options.
For any errors during execution, check the weighttp command that was issued, and refer to the weighttp documentation.


./wspwn --requests|-r NUM  --concurrent|-c MIN|MAX --concurrent-increment|-i NUM [OPTIONS] [--url|-u] URI
    Do the shit

./wspwn --help|-h|-?
    Prints the help

./wspwn --version|-v
    Shows wspwn version as well as weighttp version

URI     A url that weighttp is able to understand
OPTIONS
        --requests|-r NUM:              Total number of requests. At any time, must not
                                        be lower than the number of clients, unless
                                        --request-per-client is used.
        --request-per-client|p:         (recommended) Number of request is per client
                                        instead of total. May keep an overall same
                                        duration between each client increment.
                                        Increases the reliablity of the test since all
                                        clients are always issuing the same number of
                                        queries. Only the number of client changes.
        --threads|t NUM:                Number of threads to use.
        --clients|c MIN|MAX:            Number of concurrents clients. Arg must be
                                        present 2 times, first for min, second for max
                                        (i.e.: -c10c100 for min=10, max=100)
        --concurrent-increment|i NUM:   By how much to increase the number of concurrent
                                        clients.
        --keep-alive|k:                 Use Keep-Alive for each connection.
        --ipv6|-6:                      Use IPv6.
        --header|-H STR:                Add a http header to the request.
        --weighttp|w PATH:              weighttp location.
        --pass-through|g:               Don't wait until the end of the runs to start
                                        writing results. Result headers will be based
                                        only on the first line.
        --output|o PATH:                Save the results to a file (TSV format).
EOH
}

sub help_and_quit
{
    help;
    exit 1;
}

sub get_wh_location
{
    my $l=`which weighttp`;
    return $? == 0 ? $l : undef;
}

sub invoke_weighttp
{
    my ($clients_lvl, $nb_req, $nbt) = @_;
    my $wh_invoke= $wh_location
        . " -n $nb_req"
        . " -t $nbt"
        . " -c $clients_lvl"
        . ($ka ? " -k" : "")
        . ($ipv6 ? " -6" : "");
        
    $wh_invoke .= " -H '$_'" foreach @headers;
    
    $wh_invoke .= " '$url'";
    
    err "Executing: $wh_invoke";
    
    my $res = `$wh_invoke`;
    return $? == 0 ? $res : '';
}

sub value_key_list_to_hash
{
    my ($list, $prefix, $add_to) = @_;
    my $tmp;
    foreach(@$list)
    {
        if(not defined $tmp){$tmp=$_;}
        else{ my $v = $tmp; undef $tmp; $add_to->{$prefix ."_$_"} = $v; }
    }
}

sub format_wh_result
{
    my ($output) = @_;
    my %result;
    my @lines = split /^/m, $output;
    my $nbt = 0;
    my $nbc = 0;
    foreach(@lines)
    {
        next if /^weighttp/;
        next if /^\s*$/;
        next if /^starting benchmark/;
        next if /^progress/;
        #(++$nbt and next) if /^spawning thread/;
        if(m/^spawning thread #\d+: (\d+) concurrent requests/)
        {
            $nbt++;
            $nbc+=$1;
            next;
        }
        if(m/^finished in (\d+) sec, (\d+) millisec and (\d+) microsec, (\d+) req\/s, (\d+) (kbyte\/s)/)
        {
            $result{'total_time'} = $1 + ($2/1000) + ($3/1000000);
            $result{'req/s'} = $4;
            $result{$6} = $5;
            next;
        }
        if(my @matches = m/^requests: (\d+) (\w+), (\d+) (\w+), (\d+) (\w+), (\d+) (\w+), (\d+) (\w+), (\d+) (\w+)/)
        {
            value_key_list_to_hash(\@matches, "nbreq", \%result);
            next;
        }
        if(my @matches = m/^status codes: (\d+) (\dxx), (\d+) (\dxx), (\d+) (\dxx), (\d+) (\dxx)/)
        {
            value_key_list_to_hash(\@matches, "retcode", \%result);
            next;
        }
        if(my @matches = m/^traffic: (\d+) bytes (\w+), (\d+) bytes (\w+), (\d+) bytes (\w+)/)
        {
            value_key_list_to_hash(\@matches, "bytes", \%result);
            next;
        }
        say $_;
    }
    $result{'threads'} = $nbt;
    $result{'clients'} = $nbc;
    $result{'time/req'} = sprintf "%.6f", $result{'clients'}/$result{'req/s'};
    
    return \%result;
}

sub run_test
{
    my ($clients_lvl, $nb_reqs) = @_;
    if($clients_lvl == 0) { $clients_lvl = 1; }
    if($nb_reqs == 0) { $nb_reqs = $nreq; }
    my $nbt = $threads > $clients_lvl ? $clients_lvl : $threads;
    #say "Running test with $clients_lvl workers for $nb_reqs requests";
    my $wh_output = invoke_weighttp ($clients_lvl, $nb_reqs, $nbt);
    return format_wh_result($wh_output);
}

sub add_headers
{
    my($row_ref) = @_;
    my %seen;
    @seen{@file_headers} = ();
    
    push(@file_headers, grep { !exists $seen{$_}} keys %$row_ref );
    @file_headers = sort @file_headers;
}

sub save_headers
{
    save join "	", @file_headers;
}

sub save_line
{
    my($row_ref) = @_;
    
    if(!@file_headers) { add_headers($row_ref); save_headers; }
    
    save join "	", map { exists $row_ref->{$_} ? $row_ref->{$_} : '' } @file_headers;
    
}

sub save_all_results
{
    my ($res) = @_;
    
    add_headers($_) foreach @$res;
    save_headers;
    save_line($_) foreach @$res;
}

sub check_args
{
    ($threads, $ka, $ipv6, $req_p_c, $pt) = (2, 0, 0, 0, 0);

    $wh_location=get_wh_location;

    Getopt::Long::Configure("bundling", "no_ignore_case");

    Getopt::Long::GetOptions(                  'url|u=s' => \$url,
                                              'help|h|?' => \&help_and_quit,
                                          'requests|n=i' => \$nreq,
                                'request-per-client|p'   => \$req_p_c,
                                           'threads|t:2' => \$threads,
                                           'clients|c=i' => \@clients,
                              'concurrent-increment|i=i' => \$inc,
                                        'keep-alive|k'   => \$ka,
                                              'ipv6|6'   => \$ipv6,
                                            'header|H:s' => \@headers,
                                           'version|v'   => \&get_versions,
                                          'weighttp|w:s' => \$wh_location,
                                      'pass-through|g'   => \$pt,
                                            'output|o:s' => \$file
                            ) or help_and_quit;


    if(not defined $url and @ARGV > 0)
    {
        $url = $ARGV[0];
    }

    if(       not defined $url
        or not defined $nreq
        or @clients < 2
        or ($clients[0] > $clients[1])
        or not defined $inc
    )
    {
        help_and_quit;
    }
    if( not defined $wh_location)
    {
        say "ERROR: weighttp not found !";
        say "Please provide correct location with --weighttp option.";
        exit 2;
    }
    chomp($wh_location);

    if(defined $file)
    {
        if(open $fh, '>', $file) { select $fh; }
        else { err "Warning: cannot open file $file, using STDOUT instead"; }
    }
}

sub start_pwn
{
    check_args;

    my (@results, $clients_lvl);
    my $res;
    my $nb_steps = int (($clients[1] - $clients[0]) / $inc);
    for ($clients_lvl = $clients[0]; $clients_lvl <= $clients[1]; $clients_lvl += $inc)
    {
        print STDERR "(". ( int (int $clients_lvl/$inc) * 100 /$nb_steps )."%) ";
        $res = run_test ($clients_lvl , $req_p_c ? $clients_lvl * $nreq : $nreq );
        if($pt) { save_line($res); }
        else { push (@results, $res); }
        
    }
    if(!$pt) { save_all_results (\@results); }
}



start_pwn;
