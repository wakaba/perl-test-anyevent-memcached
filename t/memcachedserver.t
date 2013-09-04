use strict;
use warnings;
use Path::Class;
use lib file(__FILE__)->dir->parent->subdir('lib')->stringify;
use lib glob file(__FILE__)->dir->parent->subdir('t_deps', 'modules', '*', 'lib')->stringify;
use AnyEvent;
use Test::AnyEvent::Memcached::MemcachedServer;
use Test::More;
use Test::X1;
use Memcached::Client;

test {
    my $c = shift;

    my $server = Test::AnyEvent::Memcached::MemcachedServer->new;
    my $cv1 = $server->start_as_cv;

    $cv1->cb(sub {
        test {
            my $port = $server->server_port;
            ok $port;

            my $client = Memcached::Client->new({
                servers => ['localhost:'.$port],
            });

            my $cv2 = AE::cv;
            $client->set ('hoge' => 'fuga', 20, $cv2);
            $cv2->cb(sub {
                test {
                    my $cv3 = AE::cv;
                    $client->get ('hoge', $cv3);
                    $cv3->cb(sub {
                        my $result = $_[0]->recv;
                        test {
                            is $result, 'fuga', 'set -> get';
                            $server->stop_as_cv->cb(sub {
                                test {
                                    done $c;
                                    undef $c;
                                } $c;
                            });
                        } $c;
                    });
                } $c;
            });
        } $c;
    });
} n => 2;

run_tests;
