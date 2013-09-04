package Test::AnyEvent::Memcached::MemcachedServer;
use strict;
use warnings;
our $VERSION = '1.0';
use AnyEvent;
use Memcached::Server;

sub new {
    return bless {data => {}}, $_[0];
}

sub server_host {
    return '0';
}

sub server_port {
    return $_[0]->{port} ||= Test::AnyEvent::Memcached::MemcachedServer::FindPort->find_listenable_port;
}

# <https://github.com/memcached/memcached/blob/master/doc/protocol.txt#L79>
sub _xt ($) {
    return $_[0] < 60*60*24*30 ? $_[0] + time : $_[0];
}

sub server {
    my $data = $_[0]->{data};
    return $_[0]->{server} ||= Memcached::Server->new(
        cmd => {
            set => sub {
                #my ($cb, $key, $flag, $expire, $value) = @_;
                $data->{$_[1]} = [$_[4], _xt $_[3]];
                $_[0]->(1);
            },
            get => sub {
                #my ($cb, $key) = @_;
                if (exists $data->{$_[1]} and
                    _xt $data->{$_[1]}->[1] > time) { # expires
                    $_[0]->(1, $data->{$_[1]}->[0]);
                } else {
                    $_[0]->(0);
                }
            },
            _find => sub {
                #my ($cb, $key) = @_;
                $_[0]->(exists $data->{$_[1]} && _xt $data->{$_[1]}->[1] > time);
            },
            delete => sub {
                #my ($cb, $key) = @_;
                if (exists $data->{$_[1]}) {
                    if (_xt $data->{$_[1]}->[1] > time) {
                        delete $data->{$_[1]};
                        $_[0]->(1);
                    } else {
                        delete $data->{$_[1]};
                        $_[0]->(0);
                    }
                } else {
                    $_[0]->(0);
                }
            },
            flush_all => sub {
                #my ($cb) = @_;
                %$data = ();
                $_[0]->();
            },
        },
    );
}

sub start_as_cv {
    $_[0]->server->open($_[0]->server_host, $_[0]->server_port);
    my $cv = AE::cv;
    $cv->send(1);
    return $cv;
}

sub stop_as_cv {
    $_[0]->server->close_all;
    my $cv = AE::cv;
    $cv->send(1);
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

package Test::AnyEvent::Memcached::MemcachedServer::FindPort;
use Socket;

our $EphemeralStart = 1024;
our $EphemeralEnd = 5000;

our $UsedPorts = {};

sub is_listenable_port {
    my ($class, $port) = @_;
    return 0 unless $port;
    return 0 if $UsedPorts->{$port};
    
    my $proto = getprotobyname('tcp');
    socket(my $server, PF_INET, SOCK_STREAM, $proto) || die "socket: $!";
    setsockopt($server, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)) || die "setsockopt: $!";
    bind($server, sockaddr_in($port, INADDR_ANY)) || return 0;
    listen($server, SOMAXCONN) || return 0;
    close($server);
    return 1;
}

sub find_listenable_port {
    my $class = shift;
    
    for (1..10000) {
        my $port = int rand($EphemeralEnd - $EphemeralStart);
        next if $UsedPorts->{$port};
        if ($class->is_listenable_port($port)) {
            $UsedPorts->{$port} = 1;
            return $port;
        }
    }

    die "Listenable port not found";
}

sub clear_cache {
    $UsedPorts = {};
}

1;
