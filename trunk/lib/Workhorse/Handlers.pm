package Workhorse::Handlers;

use strict;
use Carp;
use Module::Find;
use Workhorse::Config;
our $VERSION = "0.01";
our $AUTOLOAD;
our $NAME = 'workhorse_handlers';
our $DESCRIPTION = 'Manages daemon functions';

=head1 NAME

Workhorse::Handlers

=head1 DESCRIPTION

Register handlers for messages

=head1 METHODS

=cut

=head2 new

 Constructor

=cut
my %fields = (
	groupchat => {},
	chat => {},
	message => undef,
	connection => undef,
	handled => undef,
);

my @Loaded = qw//;

my @toload = findsubmod Workhorse::Functions;

foreach my $m (@toload) {
	eval " require $m; import $m ; ";
	if ($@) { warn $@; } else { push (@Loaded, $m); }
}

sub new {
	my ($proto,$connection,$message) = @_;
	my $class = ref($proto) || $proto;
	my $self = {_permitted => \%fields, %fields};
	bless ($self, $class);
	return undef unless ($connection && $message);
	$self->{connection} = $connection;
	$self->{message} = $message;
	$self->{config} = Workhorse::Config::object;
	$self->_init();
	return $self;
}

sub handle_message {
	my $self = shift;
	if ($self->{message}->type =~ m/^(?:normal|chat)$/i) {
		my $chat_handler = $self->chat;
		my $users = $self->{config}->('users');

		foreach my $handle (keys %{$chat_handler}) {
			next if $handle =~ m/^_/;
			next unless ($users->{Workhorse->get_user($self->{message}->from)}->{allowed} eq 'all' or $users->{Workhorse->get_user($self->{message}->from)}->{functions}->{$handle} eq 'allowed');
			my $handler = $chat_handler->{$handle};
			eval{$self->handled(&$handler($self->connection,$self->message))};
			last if ($self->handled);
		}
		
		unless($self->handled) {
			# Hasn't been handled, default it
			return unless ($self->{config}->('global.system.enable_direct_default_response'));
			return unless ($users->{Workhorse->get_user($self->{message}->from)}->{allowed} eq 'all');
			my $handler = $chat_handler->{_default};
			$self->handled(&$handler($self->connection,$self->message));
		}
	}
}

sub handle_group_message {
	my $self = shift;

	if ($self->{message}->type =~ m/^(?:groupchat)$/i) {
		my $chat_handler = $self->groupchat;
		my $handles = $self->{config}->('handles');
		my $users = $self->{config}->('users');
		return if (Workhorse->get_handle($self->{message}->from) eq 'anonymous');
		foreach my $handle (keys %{$chat_handler}) {
			next if $handle =~ m/^_/;
			next unless ($users->{$handles->{Workhorse->get_handle($self->{message}->from)}->{link}}->{allowed} eq 'all' or $users->{$handles->{Workhorse->get_handle($self->{message}->from)}->{link}}->{functions}->{$handle} eq 'allowed');
			my $handler = $chat_handler->{$handle};
			eval{$self->handled(&$handler($self->connection,$self->message))};
			last if ($self->handled);
		}
		
		unless($self->handled) {
			# Hasn't been handled, default it
			return unless ($self->{config}->('global.system.enable_group_default_response'));
			return unless ($users->{$handles->{Workhorse->get_handle($self->{message}->from)}->{link}}->{allowed} eq 'all');
			my $handler = $chat_handler->{_default};
			$self->handled(&$handler($self->connection,$self->message));
		}
	}
}

sub _init {
	my $self = shift;
	my %chat_handle = ( _default => \&_default_handler );
	my %groupchat_handle = ( _default => \&_default_handler );
	my $functions = $self->{config}->('functions');
	foreach my $mod (@Loaded) {
		my $function = $mod->new($self->connection, $self->message);
		next unless $function;
		next unless ($functions->{$function->name} && $functions->{$function->name}->{active} eq 'yes');
		$chat_handle{$function->name} = $function->chat if ($function->chat);
		$groupchat_handle{$function->name} = $function->groupchat if ($function->groupchat);
	}
	$self->chat(\%chat_handle);
	$self->groupchat(\%groupchat_handle);
}

sub _default_handler {
	my ($connection,$message) = @_;
	return 0 unless ($connection && $message);
	my $reply = $message->make_reply;
	$reply->add_body('Sorry, I do not understand: '.$message->body);
	$reply->send;
	return 1;
	
}

sub get_loaded {
	my ($self) = shift;
	return @Loaded;
}

sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self) or croak "$self is not an object";
    my $name = $AUTOLOAD;
    $name =~ s/.*://;   # strip fully-qualified portion
    unless (exists $self->{_permitted}->{$name} ) {
        croak "Can't access `$name' field in class $type";
    }
    if (@_) {
        return $self->{$name} = shift;
    } else {
        return $self->{$name};
    }
}

sub DESTROY {
	
}

=head1 AUTHOR

Created by Derek on 2007-08-07.
Copyright (c) 2007 Compu-SOLVE Technologies, Inc. All rights reserved.

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
