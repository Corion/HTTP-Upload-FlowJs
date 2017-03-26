#!perl -w
use strict;
use warnings;
use Test::More tests => 75;
use Data::Dumper;

use HTTP::Upload::FlowJs;
use File::Temp qw(tempdir);
use ExtUtils::Command();

my $tempdir = tempdir();
END {
    if( defined $tempdir ) {
        diag "Cleaning up $tempdir";
        @ARGV = $tempdir;
        ExtUtils::Command::rm_rf $tempdir;
    };
};

my $flowjs = HTTP::Upload::FlowJs->new(
    incomingDirectory => $tempdir,
);

is $flowjs->pendingUploads, 0, "At start we have no pending uploads";
is_deeply [$flowjs->pendingUploads], [], "At start we have no pending uploads (list)";
is $flowjs->staleUploads, 0, "At start we have no stale uploads";

# Check that we can ask for the presence of a file
my( $status, @errors ) = $flowjs->chunkOK(
    {
        flowChunkNumber => 3,
        flowChunkSize => 1048576,
        flowFilename => 'IMG_7363.JPG',
        flowIdentifier => '2226376-IMG_7363JPG',
        flowRelativePath => 'IMG_7363.JPG',
        flowTotalChunks => 3,
        flowTotalSize => 2226376
    }
);
is $status, 416, "A non-existing directory+file is no error";
is_deeply \@errors, [], "The request is not obviously invalid";

# Check that different sessions get different names
   $flowjs = HTTP::Upload::FlowJs->new(
    incomingDirectory => $tempdir,
);

my %chunkName;
for my $session_id (1..3) {
    $chunkName{ $session_id } = $flowjs->chunkName(
    {
        flowChunkNumber => 3,
        flowChunkSize => 1048576,
        flowFilename => 'IMG_7363.JPG',
        flowIdentifier => '2226376-IMG_7363JPG',
        flowRelativePath => 'IMG_7363.JPG',
        flowTotalChunks => 3,
        flowTotalSize => 2226376
    }, $session_id);
};
isn't $chunkName{1}, $chunkName{2}, "Different sessions get different filenames";

   $flowjs = HTTP::Upload::FlowJs->new(
    incomingDirectory => $tempdir,
);
# Now try to "upload" a chunk much larger than what is allowed:
# Check that we can ask for the presence of a file
my %info = (
        flowChunkNumber => 1,
        flowChunkSize => 1048576,
        flowFilename => 'IMG_7363.JPG',
        flowIdentifier => '2226376-IMG_7363JPG',
        flowRelativePath => 'IMG_7363.JPG',
        flowTotalChunks => 1,
        flowTotalSize => -s $0,
        localChunkSize => 10_000_000,
        file => $0,
);
@errors = $flowjs->validateRequest(
    'POST',
    \%info,
);
is_deeply [ sort @errors ], [
    'Uploaded chunk [1] of [IMG_7363.JPG] is larger than it should be ([10000000], expect [1048576])',
], "We reject a chunk that is larger than the proposed size"
    or do { diag $_ for @errors };

# Now try to "upload" a set of too many chunks
%info = (
        flowChunkNumber => 1,
        flowChunkSize => 1048576,
        flowFilename => 'IMG_7363.JPG',
        flowIdentifier => '2226376-IMG_7363JPG',
        flowRelativePath => 'IMG_7363.JPG',
        flowTotalChunks => 1100,
        flowTotalSize => -s $0,
        localChunkSize => 1,
        file => $0,
);
@errors = $flowjs->validateRequest(
    'POST',
    \%info,
);
is_deeply [ sort @errors ], [
  'Parameter [flowTotalChunks] should be less than 1000, but is [1100]',
], "We reject a set of chunks that is larger than the proposed count";


# Now try to "upload" this chunk:
# Check that we can ask for the presence of a file
# XXX we need to create the appropriate tempfile here!
open my $testfile, '<', $0 or die "Couldn't read testfile '$0': $!";
binmode $testfile;
%info = (
        flowChunkNumber => 1,
        flowChunkSize => 1048576,
        flowFilename => 'IMG_7363.JPG',
        flowIdentifier => '2226376-IMG_7363JPG',
        flowRelativePath => 'IMG_7363.JPG',
        flowTotalChunks => 1,
        flowTotalSize => -s $0,
        localChunkSize => -s $0,
        file => $0,
);
@errors = $flowjs->validateRequest(
    'POST',
    \%info,
);
# Save the data
my $tempname = $flowjs->chunkName(\%info);
ok $tempname, 'We get a temporary filename for the chunk';
open my $fh, '>', $flowjs->chunkName(\%info)
    or die "Couldn't create '$tempname': $!";
binmode $fh;
print $fh $_ for <$testfile>;
close $fh;
is_deeply \@errors, [], "The request is not obviously invalid";
ok $flowjs->uploadComplete(\%info), "The upload is considered complete";
is $flowjs->pendingUploads, 1, "We have one pending upload (even if it's complete)";
is_deeply [$flowjs->pendingUploads], [$tempname], "We have one pending upload (even if it's complete)";


my $payload = join '',
              "\x89",
              'PNG',
              "\x0d\x0a",
              "\x1a",
              "\x0a",
              (map { chr($_) x (1024 * 1024) } 1..3)
              ;

sub chunkSize { 1_000_000 };
sub parts { int( length( $payload )/ chunkSize )+1 }
sub part {
    my( $index ) = @_;
    substr $payload, ($index-1)*chunkSize, chunkSize
}
sub part_fh {
    my $content = part(@_);
    open my $fh, '<', \$content
        or die "Couldn't open in-memory filehandle: $!";
    binmode $fh;
    
    $fh;
}

# Upload a file in three chunks, first->last->middle
# check that it's considered "complete"
# We create a fake PNG that's basically just the PNG header and then nulls
   $flowjs = HTTP::Upload::FlowJs->new(
    incomingDirectory => $tempdir,
    flowChunkSize => chunkSize,
);

my @parts = 1..parts;
my %seen;
unshift @parts, pop @parts; # favour first and last chunks
diag "Uploading sequence: @parts";
 %info = (
    flowChunkSize => chunkSize,
    flowChunkNumber => 0,
    flowTotalChunks => parts,
    flowTotalSize => length($payload),
    flowFilename => 'test.png',
    flowIdentifier => 'test.png',
    file => undef,
    localChunkSize => undef,
);

my @uploaded_parts = ($tempname); # from above
for my $chunk (@parts) {
    %info = (
        flowChunkSize => chunkSize,
        flowChunkNumber => $chunk,
        flowTotalChunks => parts,
        flowTotalSize => length($payload),
        flowFilename => 'test.png',
        flowIdentifier => 'test.png',
        file => part_fh($chunk),
        localChunkSize => length part($chunk),
    );
    $seen{ $chunk } = $info{ localChunkSize };
    @errors = $flowjs->validateRequest(
        'POST',
        \%info,
    );
    diag "Uploaded chunk $chunk";
    is_deeply [ sort @errors ], [], "No errors for chunk $chunk";
    
    # save the upload
    my $tempname = $flowjs->chunkName(\%info);
    ok $tempname, 'We get a temporary filename for the chunk';
    open my $fh, '>', $flowjs->chunkName(\%info)
        or die "Couldn't create '$tempname': $!";
    binmode $fh;
    print $fh part($chunk);
    close $fh;
    push @uploaded_parts, $tempname;
    
    my( $content_type, $ext ) = $flowjs->sniffContentType(\%info);
    if( exists $seen{1}) {
        is $content_type, 'image/png', "Once we see the first chunk, we find the correct content type";
        is $ext, 'png', "Once we see the first chunk, we find the correct extension";
    } else {
        is $content_type, undef, "Until we see the first chunk, we don't know the content type";
        is $ext, undef, "Until we see the first chunk, we don't know the extension";
    };

    is $flowjs->pendingUploads, 2, "We have twp pending uploads";
    is_deeply [sort $flowjs->pendingUploads], [ sort @uploaded_parts ],
        "We get the list of uploaded partial files";

    if( $chunk != $parts[-1]) {
        ok !$flowjs->uploadComplete( \%info ), "An incomplete upload is not complete";
    } else {
        ok $flowjs->uploadComplete( \%info ), "A complete upload is complete";
    };
};

# Check that we receive the complete file in the chunks:
if( $flowjs->uploadComplete( \%info, undef )) {
    pass "The upload is considered complete";
    
    # Combine all chunks to final name

    my $result = '';
    open my $fh, '>', \$result
        or die $!;
    binmode $fh;

    my( $ok, @unlink_chunks ) = $flowjs->combineChunks( \%info, undef, $fh );
    unlink @unlink_chunks;
    
    close $fh;
    
    ok $result eq $payload, "We can read the identical file from the parts again";
    is $flowjs->pendingUploads, 1, "After combining the chunks, the upload count decreases";
    is_deeply [$flowjs->pendingUploads], [$tempname], "Only one file remains";

} else {
    fail "The upload is considered complete";
    SKIP: {
        skip 2, "Upload was not completed, no sense in checking the files";
    }
}

# Upload a file in three chunks, first->last->middle
# check that starting with chunk 2 the chunks are rejected because we don't
# allow this MIME type here
   $flowjs = HTTP::Upload::FlowJs->new(
    incomingDirectory => $tempdir,
    allowedContentType => sub { $_[0] =~ m!^text/plain$! },
);

@parts = 1..parts;
%seen = ();
unshift @parts, pop @parts; # favour first and last chunks

is_deeply [$flowjs->pendingUploads], [$tempname], "Only one file remains";
my %uploaded_parts = ($tempname => 1);
for my $chunk (@parts, 2..parts) {
    %info = (
        flowChunkSize => chunkSize,
        flowChunkNumber => $chunk,
        flowTotalChunks => parts,
        flowTotalSize => length($payload),
        flowFilename => 'test.png',
        flowIdentifier => 'test.png',
        file => part_fh($chunk),
        localChunkSize => length part($chunk),
    );
    $seen{ $chunk } = $info{ localChunkSize };
    @errors = $flowjs->validateRequest(
        'POST',
        \%info,
    );
    is_deeply [ sort @errors ], [], "No errors for chunk $chunk";
    
    # save the upload
    my $tempname = $flowjs->chunkName(\%info);
    open my $fh, '>', $flowjs->chunkName(\%info)
        or die "Couldn't create '$tempname': $!";
    binmode $fh;
    print $fh part($chunk);
    close $fh;
    $uploaded_parts{ $tempname } = 1;

    my $res = $flowjs->disallowedContentType(\%info);
    if( exists $seen{1}) {
        is $res, 'image/png', "Once we see the first chunk, we find the file is disallowed";
    } else {
        is $res, undef, "Until we see the first chunk, we don't know if the file is disallowed";
    };

    is $flowjs->pendingUploads, 2,
        "Even invalid uploads get counted";
    is_deeply [$flowjs->pendingUploads], [ sort keys %uploaded_parts ],
        "Invalid upload parts also get listed"
        or diag Dumper { got => [$flowjs->pendingUploads], expected => [ sort keys %uploaded_parts ] };
};

# Hopefully the test suite runs below 3600 seconds
is $flowjs->staleUploads, 0, "At end we have no stale uploads";

done_testing;