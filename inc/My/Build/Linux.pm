########################################################################
                    package My::Build::Linux;
########################################################################

use strict;
use warnings;
use parent 'My::Build';
use File::ShareDir;

# We don't need any extra args for pure Linux builds, but this may be
# overridden by derived classes
sub extra_config_args { '' }

sub make_command { 'make' }

sub install_to_prefix {
	my ($self, $prefix) = @_;
	
	return if $self->notes('build_state') eq $prefix;
	
	$self->my_clean;
	
	# Get the system-specific make command
	my $make = $self->make_command;
	
	# move into the source directory and perform configure, make, and install
	chdir 'src';
	
	# Add -fPIC if it's in our Perl Config's cccdlflags
	use Config;
	$ENV{CFLAGS} = '' unless $ENV{CFLAGS};  # Avoid undef warnings
	$ENV{CFLAGS} .= ' -fPIC'
		if $Config{cccdlflags} =~ /-fPIC/ and $ENV{CFLAGS} !~ /-fPIC/;
	
	# clean followed by a normal incantation
	my $extra_args = $self->extra_config_args;
	system("./configure --prefix=$prefix $extra_args")
		and die 'tcc build failed at ./configure';
	system($make)
		and die 'tcc build failed at make';
	system($make, 'install')
		and die 'tcc build failed at make install';
	
	# Move back to the root directory
	chdir '..';
	
	# Record the current build state so we don't build more than necessary.
	$self->notes('build_state', $prefix);
}

use Cwd;
sub ACTION_code {
	my $self = shift;
	$self->notes('build_state', '') unless defined $self->notes('build_state');
	
	# Build an absolute prefix to our (local) sharedir, build and install
	my $prefix = File::Spec->catdir(getcwd(), 'share');
	$self->install_to_prefix($prefix);
	
	$self->SUPER::ACTION_code;
}

sub my_clean {
	my $self = shift;
	return unless -f 'src/config.mak';
	
	# Get the system-specific make command
	my $make = $self->make_command;
	
	chdir 'src';
	system($make, 'clean');
	chdir '..';
}

use File::Path;
sub ACTION_install {
	my $self = shift;
	
	# For unixish systems, we must re-build with the new prefix so that all of
	# the baked-in paths are correct. I just wanna say this:
	#my $prefix = File::ShareDir::dist_dir('Alien-TinyCC');
	# Unfortunately, this won't work because File::ShareDir expects the
	# folder to already exist.
	
	# Instead, I copy code from Alien::Base::ModuleBuild to calculate the
	# sharedir location by-hand:
	my $prefix = File::Spec->catdir($self->install_destination('lib'),
		qw(auto share dist Alien-TinyCC));
	
	# Completely rebuild (and install) the compiler with the new prefix
	File::Path::make_path($prefix);
	$self->install_to_prefix($prefix);
	
	# Proceed with the rest of the install
	$self->SUPER::ACTION_install;
}

### ucontext location detection patch ###

use File::Temp qw/ tempfile /;
use Config;

# Test for ucontext.h vs sys/ucontext.h
sub try_include_file {
	my $lib_name = shift;
	my ($out_fh, $out_filename) = tempfile(UNLINK => 1, SUFFIX => '.c');
	print $out_fh "#include <$lib_name>\nint main() { return 1;}";
	close $out_fh;
	print "Testing for ucontext as $lib_name...\n";
	return system("$Config{cc} $out_filename") == 0 ? $lib_name : undef;
}

my $ucontext_include = try_include_file('ucontext.h')
	|| try_include_file('sys/ucontext.h')
	|| die "Unable to locate ucontext!";

# Now patch tcc.h for the proper ucontext location
My::Build::apply_patches('src/tcc.h',
	qr{#include <sys/ucontext\.h>} => sub {
		my ($in_fh, $out_fh, $line) = @_;
		print $out_fh "#include <ucontext.h>\n";
		return 1;
	},
) if $ucontext_include eq 'ucontext.h';

1;
