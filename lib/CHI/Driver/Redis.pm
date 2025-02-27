package CHI::Driver::Redis;
use Moose;

use Check::ISA;
use Encode;
use Redis;
use Try::Tiny;
use URI::Escape qw(uri_escape uri_unescape);

extends 'CHI::Driver';

our $VERSION = '0.04';

has 'redis' => (
    is => 'rw',
    isa => 'Redis',
);

has '_params' => (
    is => 'rw'
);

sub BUILD {
    my ($self, $params) = @_;

    $self->_params($params);
}

sub _build_redis {
    my ($self) = @_;

    my $params = $self->_params;

    return Redis->new(
        server => $params->{server} || '127.0.0.1:6379',
        debug => $params->{debug} || 0
    );
}

sub fetch {
    my ($self, $key) = @_;

    return unless $self->_verify_redis_connection;

    my $eskey = uri_escape($key);
    my $val = $self->redis->hget($self->namespace, $eskey);
    # Blindly turn off the damn UTF-8 flag because Redis.pm blindly
    # turns it on. This prevents CHI from going crazy.
    Encode::_utf8_off($val);

    return $val;
}

sub get_keys {
    my ($self) = @_;

    return unless $self->_verify_redis_connection;

    my @keys = $self->redis->hkeys($self->namespace);

    my @unesckeys = ();

    foreach my $k (@keys) {
        # Getting an empty key here for some reason...
        next unless defined $k;
        push(@unesckeys, uri_unescape($k));
    }
    return @unesckeys;
}

sub get_namespaces {
    my ($self) = @_;

    return unless $self->_verify_redis_connection;

    return $self->redis->smembers('chinamespaces');
}

sub remove {
    my ($self, $key) = @_;

    return unless defined($key);

    return unless $self->_verify_redis_connection;

    my $ns = $self->namespace;

    my $skey = uri_escape($key);

    # $self->redis->srem($ns, $skey);
    $self->redis->hdel($ns, $skey);
}

sub store {
    my ($self, $key, $data, $expires_at, $options) = @_;

    return unless $self->_verify_redis_connection;

    my $ns = $self->namespace;

    my $skey = uri_escape($key);
    # my $realkey = "$ns||$skey";

    $self->redis->sadd('chinamespaces', $ns);
    # unless($self->redis->sismember($ns, $skey)) {
    #     $self->redis->sadd($ns, $skey) ;
    # }
    $self->redis->hset($ns, $skey => $data);

    # if(defined($expires_at)) {
    #     my $secs = $expires_at - time;
    #     $self->redis->expire($realkey, $secs);
    # }
}

sub _verify_redis_connection {
    my ($self) = @_;

    my $success = 0;
    try {
        if(defined($self->redis)) {
            if($self->redis->ping) {
                $success = 1;
                return;
            }
            # Bitch if the ping fails
            die "Ping failed.";
        }
    } catch {
        print STDERR "$_\n";
        warn "Error pinging redis, attempting to reconnect.\n";
    };

    return $success if $success;

    try {
        my $params = $self->_params;
        my $redis = Redis->new(
            server => $params->{server} || '127.0.0.1:6379',
            debug => $params->{debug} || 0
        );
        if(obj($redis, 'Redis')) {
            # We apparently connected, success!
            $self->redis($redis);
            $success = 1;
        } else {
            die('Failed to connect to Redis');
        }
    } catch {
        warn "Unable to connect to Redis: $_";
    };

    # Return the success of failure of the verification
    return $success;
}

__PACKAGE__->meta->make_immutable;

no Moose;

__END__

=head1 NAME

CHI::Driver::Redis - Redis driver for CHI

=head1 SYNOPSIS

    use CHI;

    my $foo = CHI->new(
        driver => 'Redis',
        namespace => 'foo',
        server => '127.0.0.1:6379',
        debug => 0
    );

=head1 DESCRIPTION

A CHI driver that uses C<Redis> to store the data.  Care has been taken to
not have this module fail in firey ways if the cache is unavailable.  It is my
hope that if it is failing and the cache is not required for your work, you
can ignore it's C<warn>ings.

=head1 TECHNICAL DETAILS

=head2 Namespaces.

Redis does not have namespaces.  Therefore, we have to do some hoop-jumping.

Namespaces are tracked in a set named C<chinamespaces>.  This is a list of all
the namespaces the driver has seen.

Keys in a namespace are stored in a set that shares the name of the namespace.
The actual value is stored as "$namespace||key".

So, to illustrate.  If you store a value C<foo: bar> in namespace C<baz>,
Redis will contain something like the following:

=head2 Encoding

This CHI driver uses Redis.pm.  Redis.pm blindly sets the UTF-8 flag to true
on anything it retrieves from Redis.  This driver blindly unsets the same
flag so that CHI can determine for itself how to encode the retrieved value.

=over 4

=head1 CONSTRUCTOR OPTIONS

C<server> and C<debug> are passed to C<Redis>.

=head1 ATTRIBUTES

=head2 redis

Contains the underlying C<Redis> object.

=head1 AUTHOR

Cory G Watson, C<< <gphat at cpan.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Cold Hard Code, LLC.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.
