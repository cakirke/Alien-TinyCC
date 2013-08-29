########################################################################
                       package My::Build;
########################################################################

use strict;
use warnings;
use parent 'Module::Build';

sub ACTION_build {
	my $self = shift;
	
	mkdir 'share';
	
	$self->SUPER::ACTION_build;
}

use File::Path;
sub ACTION_clean {
	my $self = shift;
	
	File::Path::remove_tree('share');
	$self->notes('build_state', '');
	
	# Call system-specific cleanup code
	$self->my_clean;
	
	# Call base-class code
	$self->SUPER::ACTION_clean;
}

# This one's an author action, so I assume they have git and have properly
# configured.
sub ACTION_dist {
	my $self = shift;
	
	# Reset the tcc source code. This only makes sense if the person has
	# src checked out as a git submodule, but then again, this is an author
	# action, so that's not an unreasonable expectation.
	chdir 'src';
	system qw( git reset --hard HEAD );
	chdir '..';
	
	# Call base class code
	$self->SUPER::ACTION_dist;
}

sub apply_patches {
	my ($filename, @patches) = @_;
	
	# make the file read-write
	chmod 0700, $filename;
	
	open my $in_fh, '<', $filename;
	open my $out_fh, '>', "$filename.new";
	LINE: while (my $line = <$in_fh>) {
		# Apply each basic test regex, and call the function if it matches
		for (my $i = 0; $i < @patches; $i += 2) {
			if ($line =~ $patches[$i]) {
				my $next_line = $patches[$i+1]->($in_fh, $out_fh, $line);
				next LINE if $next_line;
			}
		}
		print $out_fh $line;
	}
	
	close $in_fh;
	close $out_fh;
	unlink $filename;
	rename "$filename.new" => $filename;
}

1;
