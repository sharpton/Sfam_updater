package Sfam_updater::DB_op;
use strict;
use DBI;
use MRC;
use MRC::DB;
use Bio::SeqIO;
use Data::Dumper;

# Need to extract all of the new CDS from the DB
# Need to oragnize the information in manageable pieces

# gather_CDS
#
# Arguments : Database link, Username, Password, Output directory
#
# Will gather all the CDS that are not familymembers from the MySQL DB and
# write them to files ($DIV_SIZE max sequences per file) in fasta format
#
sub gather_CDS {
	my %args       = @_;
	my $output_dir = $args{output_dir};
	my $db         = $args{db};
	my $username   = $args{username};
	my $password   = $args{password};
	my $fragmented = $args{fragmented};    #fragment the output in smaller pieces 1 or 0
	my $old        = $args{old};           #gather family members or not (1 or 0)

	#if the output_dir does not exists create it.
	print "Creating $output_dir\n" unless -e $output_dir;
	`mkdir $output_dir`            unless -e $output_dir;

	my $DB = DBI->connect( $db, "$username", "$password" ) or die "Couldn't connect to database : ".DBI->errstr;
	my $count_statement = "SELECT COUNT(g.gene_oid) FROM genes g WHERE g.type=\'CDS\' AND g.gene_oid ";
	my $prepare_statement = "SELECT g.gene_oid, g.protein FROM genes g WHERE g.type=\'CDS\' AND g.gene_oid ";
	$prepare_statement .= "NOT " unless $old;
	$prepare_statement .= "IN (SELECT f.gene_oid FROM familymembers f)";
	print STDERR "prepare_statement: $prepare_statement\n";
	my $query = $DB->prepare($prepare_statement);
	$query->execute();
	my $total_seqs = count_all_CDS(	old        => 0,
									db         => $DB_pointer,
									username   => $username,
									password   => $password,
	);
	my $div_size = int($total_seq \ 14);
	my $count       = 0;
	my $div         = 1;
	my $output_file = $output_dir."/";
	$output_file .= $old ? "familymembers" : "newCDS";
	my $file_core = $output_file;
	$output_file .= $fragmented ? "_$div" : "";
	$output_file .= ".fasta";
	print STDERR "OUTPUT_file $output_file\n";
	open( OUT, ">$output_file" ) || die "Can't open $output_dir/"."newCDS_$div.fasta for writing: $!\n";

	while ( my @results = $query->fetchrow() ) {
		$count++;
		if ( $count % $div_size == 0 && $fragmented ) {
			close(OUT);
			$div++;
			open( OUT, ">$output_dir/"."newCDS_$div.fasta" ) || die "Can't open $output_dir/"."newCDS_$div.fasta for writing: $!\n";
		}
		print OUT ">$results[0]\n$results[1]\n";
	}
	close(OUT);
	print "Inside db_gather_all_non_familymembers_CDS\n";
	print "Found $count sequences\n";
	return $file_core;
}


sub insert_familymembers{
	my %args = @_;
	my $input_file = $args{input};
	my $db         = $args{db};
	my $username   = $args{username};
	my $password   = $args{password};
	my $output_dir = $args{output};
	#if the output_dir does not exists create it.
	print "Creating $output_dir\n" unless -e $output_dir;
	`mkdir -p $output_dir`         unless -e $output_dir;
	my $analysis = MRC->new();
	$analysis->set_dbi_connection($db_pointer);
	$analysis->set_username($username);
	$analysis->set_password($password);
	$analysis->build_schema();
	open(IN, $input_file) or die "Can't open $input_file for reading: $!\n";
	while(<IN>){
		chomp($_);
		next if  $_ =~ m/^#/;
		my @line = split(/\t/,$_);
		my $seq = $line[0];
		my $family = $line[1];
		my $gene = $analysis->get_gene_from_gene_oid($seq);
		open(OUT,">>$output_dir/$family_newCDS.fasta")|| die "Can't open $output_dir/$family_newCDS.fasta for writing : $!\n";
		print OUT ">".$seq."\n".$gene->{"protein"}."\n";
		close(OUT);
		$analysis->insert_familymember($family, $seq);
	}
	close(IN);
}

sub insert_fc{
	my %args = @_;
	my $db         = $args{db};
	my $username   = $args{username};
	my $password   = $args{password};
	my $author         = $args{author};
	my $description   = $args{description};
	my $name   = $args{name};
	my $analysis = MRC->new();
	$analysis->set_dbi_connection($db_pointer);
	$analysis->set_username($username);
	$analysis->set_password($password);
	$analysis->build_schema();
	$analysis->insert_family_construction($description,$name,$author);
	return 1;
}

sub count_all_CDS{
	my %args       = @_;
	my $output_dir = $args{output_dir};
	my $db         = $args{db};
	my $username   = $args{username};
	my $password   = $args{password};
	my $fragmented = $args{fragmented};    #fragment the output in smaller pieces 1 or 0
	my $old        = $args{old};           #gather family members or not (1 or 0)

	#if the output_dir does not exists create it.
	print "Creating $output_dir\n" unless -e $output_dir;
	`mkdir $output_dir`            unless -e $output_dir;

	my $DB = DBI->connect( $db, "$username", "$password" ) or die "Couldn't connect to database : ".DBI->errstr;
	my $count_statement = "SELECT COUNT(g.gene_oid) FROM genes g WHERE g.type=\'CDS\' AND g.gene_oid ";
	$count_statement .= "NOT " unless $old;
	$count_statement .= "IN (SELECT f.gene_oid FROM familymembers f)";
	print STDERR "prepare_statement: $prepare_statement\n";
	my $count_query = $DB->prepare($count_statement);
	$count_query->execute();
	my $total_seqs = $count_query->fetchrow();
	return $total_seqs;
}

sub add_new_family_members {
	my %args = @_;
	my $fam_members_file = $args{family_members_file};
	my $username = $args{username};
	my $password = $args{password};
	my $db_pointer = $args{db};
	my $analysis = MRC->new();
	$analysis->set_dbi_connection($db_pointer);
	$analysis->set_username($username);
	$analysis->set_password($password);
	$analysis->build_schema();
	open(IN,$fam_members_file) || die "Couldn't open $fam_members_file for reading : $!\n";
	while(<IN>){
		next if $_ =~ /#/; #skip if there is a header;
		$_ =~ m/^(\d+)\s+(\d+)/;
		my $new_Seq = $1;
		my $family = $2;
		$analysis->insert_familymember($family,$new_Seq);
	}	

	close(IN);
}

sub get_all_famid{
	my %args = @_;
	my $username = $args{username};
	my $password = $args{password};
	my $db_pointer = $args{db};
	my $DB = DBI->connect( $db_pointer, "$username", "$password" ) or die "Couldn't connect to database : ".DBI->errstr;
	my $results_ref = $DB->selectall_arrayref('SELECT famid FROM family WHERE 1');
	return $results_ref;
}

sub add_new_genomes {
	my %args            = @_;
	my $username        = $args{username};
	my $password        = $args{password};
	my $db_pointer      = $args{db};
	my $genome_tab_file = $args{genome_file};
	my $analysis        = MRC->new();
	$analysis->set_dbi_connection($db_pointer);
	$analysis->set_username($username);
	$analysis->set_password($password);
	$analysis->build_schema();
	my %return_gene_oids = ();

	#parse the genome table
	open( IN, $genome_tab_file ) || die "Can't open $genome_tab_file for read: $!\n";
	my $header = <IN>;
	chomp($header);
	my @cols = split( "\t", $header );
	for ( my $i = 0; $i < scalar(@cols); $i++ ) {
		$cols[$i] =~ s/\s+/_/g;
	}
	my $count = 0;
	while (<IN>) {
		chomp $_;
		my @data = split( "\t", $_ );
		my %genome = ();
		for ( my $i = 0; $i < scalar(@data); $i++ ) {
			my $key = $cols[$i];
			$key =~ s/\s/\_/g;
			my $value = $data[$i];
			$genome{$key} = $value;
		}
		print STDERR "Inserting ".$genome{"taxon_oid"}."\n";
		$analysis->MRC::DB::insert_genome_from_hash( \%genome );
		$count++;
		$return_gene_oids{ $genome{"taxon_oid"} } = 1;
	}
	close IN;
	return \%return_gene_oids;
}

sub have_genes_been_added {
	my %args       = @_;
	my $username   = $args{username};
	my $password   = $args{password};
	my $db_pointer = $args{db};
	my $genome     = $args{genome};
	my $DB         = DBI->connect( $db_pointer, "$username", "$password" ) or die "Couldn't connect to database : ".DBI->errstr;
	my $query      = $DB->prepare("SELECT g.gene_oid FROM genes g WHERE g.taxon_oid = ? ");
	$query->execute($genome);
	return 1 if $query->fetchrow();
	return 0;
}

sub add_new_genes {
	my %args             = @_;
	my $username         = $args{username};
	my $password         = $args{password};
	my $db_pointer       = $args{db};
	my $genome_tab_file  = $args{genome_file};
	my $genomes_oids_ref = $args{genome_oid_array};
	my $new_cds_dump_dir = $args{new_cds_dump_dir};
	my %genomes          = %{$genomes_oids_ref};
	my $ffdb_master      = $args{db_master};
	my $analysis         = MRC->new();
	$analysis->set_dbi_connection($db_pointer);
	$analysis->set_username($username);
	$analysis->set_password($password);
	$analysis->build_schema();
	my $div   = 1;
	my $count = 0;

	#if the output_dir does not exists create it.
	print "Creating $new_cds_dump_dir\n" unless -e $new_cds_dump_dir;
	`mkdir $new_cds_dump_dir`            unless -e $new_cds_dump_dir;
	open( OUT, ">$new_cds_dump_dir/"."newCDS_$div.fasta" ) || die "Can't open $new_cds_dump_dir/"."newCDS_$div.fasta for writing: $!\n";
	foreach my $taxon_oid ( keys %genomes ) {
		print "Processing $taxon_oid\n";
		next if have_genes_been_added(
									   username => $username,
									   password => $password,
									   db       => $db_pointer,
									   genome   => $taxon_oid
		);

		#verify that the genome is indeed in the database
		my $genome = $analysis->get_schema->resultset("Genome")->find( { taxon_oid => $taxon_oid, } );

		#my $genome = $analysis->MRC::DB::get_genome_from_taxon_oid($taxon_oid);
		my $taxon_dir;
		if ( defined($genome) ) {
			$taxon_dir = $genome->directory();
		} else {
			warn "Couldn't find taxon_oid $taxon_oid in our MySQL DB\nSkipping $taxon_oid\n";
			next;
		}
		my $taxon_full_dir = $ffdb_master.$taxon_dir."/";
		if ( !-d $taxon_full_dir ) {
			warn("$taxon_dir does not exist for $taxon_oid\n");
			next;
		}
		my $taxon_genes_info = $taxon_full_dir.$taxon_oid.".genes_info.gz";
		my $taxon_genes      = $taxon_full_dir.$taxon_oid.".ffn.gz";
		my $taxon_peptides   = $taxon_full_dir.$taxon_oid.".faa.gz";
		my %pmap             = %{ build_sequence_map($taxon_peptides) };      #maps gene_oid to sequence, might need lookup magic to make work
		my %gmap             = %{ build_sequence_map($taxon_genes) };         #maps gene_oid to sequence, might need lookup magic to make work
		open( TAB, "zcat $taxon_genes_info |" ) || die "Can't open $taxon_genes_info for read: $!\n";
		my $header = <TAB>;
		my @head   = split( "\t", $header );

		while (<TAB>) {
			chomp $_;

			#get the gene's data
			my @data = split( "\t", $_ );
			my $gene_oid = $data[0];
			print "Processing $gene_oid from taxon $taxon_oid\n";
			my %info = ();
			for ( my $i = 1; $i < scalar(@data); $i++ ) {
				$info{ $head[$i] } = $data[$i];
			}

			#need to hand tune some variables
			#tune strand
			if ( _is_defined( $info{"Strand"}, "strand", $taxon_oid ) ) {
				if ( $info{"Strand"} eq "+" ) {
					$info{"strand"} = 1;
				} elsif ( $info{"Strand"} eq "-" ) {
					$info{"strand"} = -1;
				} else {
					$info{"strand"} = 0;
				}
			} else {
				$info{"strand"} = 0;    #unknown
			}

			#tune type
			if ( _is_defined( $info{"Description"} ) ) {
				if ( $info{"Description"} =~ m/\s\(\s(.*)\s\)/ ) {
					$info{"type"} = $1;
				} else {
					$info{"type"} = "CDS";
				}
			} else {
				$info{"type"} = " ";
			}

			#tune locus
			if ( !( _is_defined( $info{"Locus Tag"} ) ) ) {
				exit(0);
			}

			#tune scaffold name and id
			if ( _is_defined( $info{"Scaffold Name"} ) ) {
				if ( $info{"Scaffold Name"} =~ m/(.*)\:(.*)/ ) {
					$info{"scaffold_name"} = $1;
					$info{"scaffold_id"}   = $2;
				} else {
					warn( "Couldn't parse scaffold data: ".$info{"Scaffold Name"}."\n" );
					exit(0);
				}
			} else {
				exit(0);
			}
			if ( !( _is_defined( $info{"Gene Symbol"} ) ) ) {
				$info{"Gene Symbol"} = "NULL";
			}

			#test print here. need to figure out protien_id first, though it *is* optional...
			my $protein_id = "NULL";
			if ( defined( $pmap{$gene_oid}->{"acc"} ) ) {
				$protein_id = $pmap{$gene_oid}->{"acc"};
			}
			if ( !defined( $pmap{$gene_oid}->{"seq"} ) ) {
				warn("Can't find protein sequence for $gene_oid from taxon $taxon_oid! Setting to NULL!\n");
				$pmap{$gene_oid}->{"seq"} = "NULL";
			}
			if ( !defined( $gmap{$gene_oid}->{"seq"} ) ) {
				warn("Can't find nucleotide sequence for $gene_oid from taxon $taxon_oid! Exiting!\n");
				print Dumper %{ $gmap{$gene_oid} }."\n";
				exit(0);
			}
			$analysis->MRC::DB::insert_gene(
											 $gene_oid,                 $taxon_oid,           $protein_id,            $info{"type"},
											 $info{"Start Coord"},      $info{"End Coord"},   $info{"strand"},        $info{"Locus Tag"},
											 $info{"Gene Symbol"},      $info{"Description"}, $info{"scaffold_name"}, $info{"scaffold_id"},
											 $gmap{$gene_oid}->{"seq"}, $pmap{$gene_oid}->{"seq"}
			);
			if ( $info{"type"} eq 'CDS' ) {
				$count++;
				if ( $count % $DIV_SIZE == 0 ) {
					close(OUT);
					$div++;
					open( OUT, ">$new_cds_dump_dir/"."newCDS_$div.fasta" ) || die "Can't open $new_cds_dump_dir/"."newCDS_$div.fasta for writing: $!\n";
				}
				print OUT ">$gene_oid\n".$pmap{$gene_oid}->{"seq"}."\n";
			}
		}
		close TAB;
	}
	close(OUT);
}

sub _is_defined {
	my ( $var, $name, $id ) = @_;
	if ( defined($var) ) {
		return 1;
	} else {
		warn("Variable $name isn't defined for $id");
		return 0;
	}
}

sub build_alt_map {
	my $file = shift;
	my %map  = ();
	open( IN, "zcat $file |" ) || die "Can't open $file: $!\n";
	while (<IN>) {
		chomp $_;
		next if ( $_ =~ m/^\#/ );
		my ( $old, $new ) = split( "\t", $_ );
		$map{$old} = $new;
	}
	close IN;
	return \%map;
}

sub build_taxonid_lookup {
	my $file   = shift;
	my %taxids = ();
	open( IN, "zcat $file |" ) || die "Can't open $file: $!\n";
	while (<IN>) {
		chomp $_;
		next unless ( $_ =~ m/^\>/ );
		if ( $_ =~ m/>TX(\d+)ID/ ) {
			$taxids{$1}++;
		}
	}
	close IN;
	return \%taxids;
}

#build this function!
sub build_sequence_map {
	my ($file) = shift;
	my %map = ();
	my $inseqs = Bio::SeqIO->new( -file => "zcat $file |", -format => 'fasta' );
	while ( my $seq = $inseqs->next_seq() ) {
		my $id       = $seq->display_id();
		my $sequence = $seq->seq();
		my $acc      = $seq->desc();
		if ( $acc =~ m/(.*?)\s.*/ ) {
			$acc = $1;
		}
		$map{$id}->{"seq"} = $sequence;
		$map{$id}->{"acc"} = $acc;
	}
	return \%map;
}
