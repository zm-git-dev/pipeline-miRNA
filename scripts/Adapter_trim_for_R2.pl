#!/usr/bin/perl
#12.07.09
#Author: zhuerle@163.com; edit by gongjing 2012-1-6;
#script for moving low quality and 3' 5' adapter and polyA

#use Statistics::R;
use File::Basename;
use strict;
use Getopt::Std;
use vars qw($opt_i $opt_n $opt_x $opt_y $opt_f $opt_h $opt_o);
getopts('i:n:x:y:l:f:h:o:');
my $fq_file        = $opt_i;
my $sp_name				 = $opt_n ? $opt_n : "sample";
my $adapter5       = $opt_x ? $opt_x : "CTTGGCACCCGAGAATTCCA";
my $adapter3       = $opt_y ? $opt_y : "GATCGTCGGACTGTAGAACTCTGAAC";
my $format         = $opt_f ? $opt_f : 2;
my $help           = $opt_h ? 1 : 0;
my $outfile		   = $opt_o;


my $usage = << "USAGE";

Description: Perl script used to filter low quality short reads, remove polyA and trim 3' 5' adapter
Author: zhuerle\@163.com
Usage: perl Adapter_trim.pl [options] >outputfile
Options:
  -i <file>  Short reads file in fastq format 
  -n <str>   Sample name; default="sample"
  -x <str>   5\' adaptor sequence, default="GTTCAGAGTTCTACAGTCCGACGATC"
  -y <str>   3\' adaptor sequence, default="TGGAATTCTCGGGTGCCAAG"
  -f <int>   Fastq file format: 1=Illumina 1.3 format; 2=Illumina 1.8+ format; default=2
  -h         Help
  -o 		 outfile
Examples: perl Adapter_trim.pl -i sample.fq -n "newid" -f 1 -o outputfile
          perl Adapter_trim.pl -i sample.fq -x "ATCGGGCT" -y "TCGTAT" -f 3 -o outputfile
USAGE

if ($help) 
{
        print $usage;
		exit;
}

unless (( -e $fq_file ) and ( $adapter5 =~ /[A|T|C|G]/i ) and ( $adapter3 =~ /[A|T|C|G]/i ) and ( $format =~ /^[1|2|3]$/ )) 
	{
		print $usage;
		exit;
	}

my $outdir  = dirname ($outfile);
my $stat    = $outdir."/sequence.stat";
my $clean_stat= $outdir."/sequence_clean.stat";
my $gc      =  $outdir."/GC_distribution";
my $txt		= $outdir."/sequence_cluster.txt";

$adapter3 =~ tr/atcg/ATCG/;
$adapter5 =~ tr/atcg/ATCG/;

my $qlt_asc;
if ($format == 1)
{
	$qlt_asc=64;
}
elsif ($format == 2)
{
	$qlt_asc=33;
}

## fliter low quality
open (IN,"$fq_file") or die $!;
my $total;
my $high_qlt_total;
my %reads_number;	##save high quality reads;
while (<IN>)
{
	my $read = <IN>;
	 $read =~ tr/atcg/ATCG/;
	chomp $read;
	<IN>;
	my $quality_line = <IN>;
	chomp $quality_line;
	$total++; 
	my $quality=0; 
	if(&check_qlt($quality_line,$qlt_asc,20))
	{
		$high_qlt_total++;
		$reads_number{$read}++;									
	}
}
close IN;

#foreach my $read (keys %reads_number){
#print "$read\t$reads_number{$read}\n";
#}

###move 3' adapter
my %after_mv3;
my $total_mv3;
foreach my $read (keys %reads_number)
{	
	my $read_af3 = &mvadapter($read,$adapter3,0);
	
	$after_mv3{$read_af3}+=$reads_number{$read} ;
}
undef(%reads_number);

#foreach my $read (sort {$after_mv3{$b}<=>$after_mv3{$a}} keys %after_mv3){print ">$after_mv3{$read}\n$read\n";}exit;
###move 5' adapter
my %after_mv5;
my $total_mv5;
foreach my $read (keys %after_mv3)
{	
	 $total_mv3+=$after_mv3{$read} ;   #here, count the total reads after removing the 3 adapter;
	my $read_af5= &mvadapter($read,$adapter5,1);
	$after_mv5{$read_af5}+=$after_mv3{$read} ;
}
undef(%after_mv3);
	
###mv polyA
my $total_mvpolyA;
my %after_mvpolyA;
foreach my $read (keys %after_mv5)
{	
	 $total_mv5+=$after_mv5{$read};              #here, count the total reads after removing the 5 adapter;
	my $polya= &mvpolyA($read);
	if($polya == 0)
	{
		$total_mvpolyA+=$after_mv5{$read};
		$after_mvpolyA{$read}=$after_mv5{$read};
	}
}
undef(%after_mv5);

###give out the 15nt~30nt clean reads
my %clean;
my %raw_len;
my $total_len;
foreach my $read (keys %after_mvpolyA)
{
	my	$len=length($read);
	$raw_len{$len}->{"uniq"}++;
	$raw_len{$len}->{"total"}+=$after_mvpolyA{$read};
	$total_len+=$after_mvpolyA{$read};
	if($len>=15 and $len<=30)
	{
		$clean{$read}=$after_mvpolyA{$read};
	}
}
undef(%after_mvpolyA);

###print 
open OUTFA,">$outfile" or die $!;
open TXT, ">$txt" or die $!;
my (%uniq, %total_len, %count);
my $num=0;
my $total_clean;
foreach my $r (sort {$clean{$b} <=> $clean{$a}} keys %clean )
{
	print OUTFA ">$sp_name".'_'.$num.'_x'.$clean{$r}."\n";
	my $r_new=$r;
	$r_new=~ tr/ATGC/TACG/;
	$r_new = reverse($r_new);
	print OUTFA "$r_new\n";
	$num++;
	
	print TXT "$r_new\t$clean{$r}\n";
	### get the length distribution;
	my $length=length $r;
	$uniq{$length}++;
	$total_len{$length}+=$clean{$r};
	$total_clean+=$clean{$r};
	my @data=split(//,$r_new);

	for(my $i=0;$i<=$#data;$i++){
		$count{$data[$i]}->{$i}=$count{$data[$i]}->{$i}+$clean{$r};
	}
}

open (OUT, ">$stat") or die "cannot open sequence.stat\n";
print OUT "Total reads:",$total,"\n" ; 
print OUT "after rm 3 adapter reads:",$total_mv3,"\n" ;
print OUT "after rm 5 adapter reads:",$total_mv5,"\n" ;
print OUT "after rm polyA:",$total_mvpolyA,"\n";
print OUT "total 15-30nt clean reads:",$total_clean,"\n";
print OUT "unique reads: $num\n";

open (OUT2, ">$clean_stat") or die "cannot open sequence_clean.stat\n";
print OUT2 "length\tunique\ttotal\n";
foreach my $l (sort keys %uniq)
{
	print OUT2 "$l\t$uniq{$l}\t$total_len{$l}\n";
}

open (OUT3, ">$gc") or die "cannot open GC_distribution";
print OUT3 "Base";
for(my $len=1;$len<=30;$len++)
{
	print OUT3 "\t$len";
}
print OUT3 "\n";
my @bp=("A","T","G","C");
foreach my $key (@bp) 
{
	print OUT3 "$key";   
	for(my $i=0;$i<=29;$i++)
	{
		my  $total_r=$count{A}->{$i}+$count{C}->{$i}+$count{T}->{$i}+$count{G}->{$i};
		if($total_r>0)
		{
			 my $rate=$count{$key}->{$i}/$total_r ;
			 printf OUT3 "\t%.3f",   "$rate";
		}
	} 
		print OUT3 "\n";
}

###############################################################################################3
#plot;
#my $length_pdf=$outdir."/length_distribution.pdf";
#my $R = Statistics::R->new() ;  
#  $R->startR ;
#my $r=<<END;
#  a<-read.table("$clean_stat",sep="\\t",header=TRUE)\n
#  pdf("$length_pdf")\n
#  C<-round(a\$total/sum(a\$total)*100,1)\n
#  barplot(C, names.arg=c(a[,1]),col=rainbow(length(a[,1])),main=c("smRNA length distribution"), ylim=c(0,max(C)+2),xlab="Clean read length", ylab="%",font.lan=1)\n
#  #barplot(C)\n
#  dev.off()\n
#END
#  $R->run($r);
  
#plot2 GC;
#my $gc_pdf=$outdir."/GC.pdf";
#my $gc_infile=$outdir."/GC_distribution";
#my $r2=<<END;
#gc<-read.table("$gc_infile",sep="\\t",header=TRUE)\n
# pdf("$gc_pdf")\n
# len<-length(gc[1,])\n
# gcc<-as.matrix(gc[,2:(len-1)])\n
# barplot(gcc, col=rainbow(4),main=c("Each site GC percent"), ylim=c(0,1), xlim=c(0,len+10), xlab="Clean read each site", ylab="%",font.lab=1)\n
# legend(len+3,0.8,legend=c("A","T","G","C"),fill=rainbow(4))\n
# dev.off()\n
#END
#  $R->run($r2);
#  $R->stop();

#########################################################################################################
#########################################################################################################
#########################################################################################################
#########################################################################################################
# 1,check while the 3 adapter is right; 2,check the qulity threshold, 33 or 64;
sub para_check{
	open IN, "$fq_file" or die $!;
	my $i=0;
	my @quality;
	my $qlt;
	while(<IN>){
		<IN>;
		<IN>;
		my $quality_line=<IN>;
		$i++;
		chomp($quality_line);
		if($i<=1000){						#test 1000 reads;
			push @quality,$quality_line;
			if(&check_qlt($quality_line,64,20)){
				$qlt++;
			}
		}
	close IN;
	if($qlt>800){
		$qlt_asc=64;
	}
	else{
		$qlt_asc=33;
	}
	}
	return $qlt_asc;
}

sub check_qlt
{
	my $quality_line = shift;
	my $asc = shift;
	my $tv = shift;
	my $num = 0;
	my $count = 0;
	my @ql = split (//,$quality_line);
	my $wid = $#ql+1;
	foreach my $i (0..$#ql)
	{
		$num = ord($ql[$i])-$asc;
		if($num-$tv <0){$count++;}
	}

		if( $count > $wid/2 ){return 0;}
		else {return 1;}
	
}


sub mvadapter
{
	my $read = shift;
	my $adapter = shift;
	my $mode = shift;
	my $readback="";
	my @record=();
	if ($mode == 1)
	{
		$read = reverse($read);
		$adapter = reverse($adapter);	
		my $bl= length($read);
		my $tl= length($adapter);
		my @bemapped=split(//,$read);
		my @tomap=split(//,$adapter);
		for (my $i =0; $i<$bl;$i++)
		{
			my $match =0;
			my $mismatch = 0;
			for (my $n=0;$n<$tl;$n++)
			{
				last unless( $bemapped[$i+$n]);
				if($bemapped[$i+$n] eq $tomap[$n]){$match++;}
				else 
				{
					$mismatch++;
					last if ($mismatch >2);
				}		
			}
			my $long= $match+$mismatch;
			my $per = sprintf "%.2f",$mismatch/($match+$mismatch);
			if($mismatch <=2 and $per < 0.1 and $long >=10)
			{
				push @record ,[$per,$i,$mismatch,$match];
			}	
		}
	}
	if ($mode == 0)
	{
		my $bl= length($read);
		my $tl= length($adapter);
		my @bemapped=split(//,$read);
		my @tomap=split(//,$adapter);
		for (my $i =0; $i<$bl;$i++)
		{
			my $match =0;
			my $mismatch = 0;
			for (my $n=0;$n<$tl;$n++)
			{
				last unless( $bemapped[$i+$n]);
				if($bemapped[$i+$n] eq $tomap[$n]){$match++;}
				else 
				{
					$mismatch++;
					last if($mismatch >2);
				}		
			}
			my $long= $match+$mismatch;
			my $per = sprintf "%.2f",$mismatch/($match+$mismatch);
			if($mismatch <=2 and $per <=0.1 and $long >=15)
			{
				push @record ,[$per,$i,$mismatch,$match];
			}	
		}
	}
	if ($#record == 0)
	{ 
		$readback = substr($read,0,$record[0][1]);
		if ($mode ==1){$readback = reverse $readback;}
	}
	elsif($#record > 0)
	{
		my @record_sort = sort {$a->[0] <=> $b->[0]} @record;
		$readback = substr($read,0,$record_sort[0][1]);
		if ($mode ==1){$readback = reverse $readback;}
	}
	else {$readback = $mode ? reverse($read) : "null";}
	return $readback;
}


sub mvpolyA 
{
	my $read = shift;
	if($read =~ /^A{6,}|^T{6,}/i)
	{	
		print "PolyA\n";
		return 1;
	}
	else 
	{
		return 0;
	}
}
