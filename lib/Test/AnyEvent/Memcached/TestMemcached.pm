package Test::AnyEvent::Memcached::TestMemcached;
use strict;
use warnings;
our $VERSION = '1.0';
use AnyEvent;
use AnyEvent::Worker;

sub new {
    return bless {}, $_[0];
}

sub worker {
    my $self = $_[0];
    return $self->{worker} ||= do {
        my $w = AnyEvent::Worker->new({
            class => 'Test::AnyEvent::Memcached::TestMemcached::Worker',
            new => 'new',
        }, on_error => sub {
            my ($worker, $error, $fatal, $file, $line) = @_;
            die "$error at $file line $line" if $fatal;
            warn "$error at $file line $line";
        });
        $w->do('install_signal_handlers', sub { });
        $w;
    };
}

sub server_host {
    return '0';
}

sub server_port {
    return $_[0]->{server_port}; # or undef
}

sub start_as_cv {
    my $self = $_[0];
    my $cv = AE::cv;
    $cv->begin;
    $cv->begin;
    $self->worker->do('start', sub { $cv->end });
    $cv->begin;
    $self->worker->do('get_server_port', sub { $self->{server_port} = $_[1]; $cv->end });
    $cv->end;
    return $cv;
}

sub stop_as_cv {
    my $cv = AE::cv;
    $_[0]->worker->do('stop', sub { $cv->send(1) });
    return $cv;
}

sub DESTROY {
    {
        local $@;
        eval { die };
        if ($@ =~ /during global destruction/) {
            warn "Detected (possibly) memory leak";
        }
    }

    $_[0]->stop_as_cv;
}

package Test::AnyEvent::Memcached::TestMemcached::Worker;

sub new {
    return bless {}, $_[0];
}

sub memcached {
    require Test::Memcached;
    return $_[0]->{memcached} ||= Test::Memcached->new;
}

sub start {
    $_[0]->memcached->start;
}

sub stop {
    $_[0]->memcached->stop;
}

sub get_server_port {
    return $_[0]->memcached->option('tcp_port');
}

sub install_signal_handlers {
    my $self = shift;
    $SIG{INT} = $SIG{QUIT} = $SIG{TERM} = sub {
        $self->stop;
        exit;
    };
    return 1;
}

1;
