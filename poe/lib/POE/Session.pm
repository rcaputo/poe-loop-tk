# $Id$

# Copyright 1998 Rocco Caputo <troc@netrus.net>.  All rights reserved.
# This program is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.

package POE::Session;

use strict;
use Carp;
use POSIX qw(ENOSYS);

use Exporter;
@POE::Session::ISA = qw(Exporter);
@POE::Session::EXPORT = qw(OBJECT SESSION KERNEL HEAP STATE SENDER
                           ARG0 ARG1 ARG2 ARG3 ARG4 ARG5 ARG6 ARG7 ARG8 ARG9
                          );

sub OBJECT  () {  0 }
sub SESSION () {  1 }
sub KERNEL  () {  2 }
sub HEAP    () {  3 }
sub STATE   () {  4 }
sub SENDER  () {  5 }
sub ARG0    () {  6 }
sub ARG1    () {  7 }
sub ARG2    () {  8 }
sub ARG3    () {  9 }
sub ARG4    () { 10 }
sub ARG5    () { 11 }
sub ARG6    () { 12 }
sub ARG7    () { 13 }
sub ARG8    () { 14 }
sub ARG9    () { 15 }

sub SE_NAMESPACE () { 0 }
sub SE_OPTIONS   () { 1 }
sub SE_KERNEL    () { 2 }
sub SE_STATES    () { 3 }

#------------------------------------------------------------------------------

sub new {
  my ($type, @states) = @_;

  my @args;

  croak "sessions no longer require a kernel reference as the first parameter"
    if ((@states > 1) && (ref($states[0]) eq 'POE::Kernel'));

  croak "$type requires a working Kernel"
    unless (defined $POE::Kernel::poe_kernel);

  my $self = bless [ { }, { } ], $type;

  while (@states) {
                                        # handle arguments
    if (ref($states[0]) eq 'ARRAY') {
      if (@args) {
        croak "$type must only have one block of arguments";
      }
      push @args, @{$states[0]};
      shift @states;
      next;
    }

    if (@states >= 2) {
      my ($state, $handler) = splice(@states, 0, 2);

      unless ((defined $state) && (length $state)) {
        carp "depreciated: using an undefined state";
      }

      if (ref($state) eq 'CODE') {
        croak "using a CODE reference as an event handler name is not allowed";
      }
                                        # regular states
      if (ref($state) eq '') {
        if (ref($handler) eq 'CODE') {
          $self->register_state($state, $handler);
          next;
        }
        elsif (ref($handler) eq 'ARRAY') {
          foreach my $method (@$handler) {
            $self->register_state($method, $state);
          }
          next;
        }
        else {
          croak "using something other than a CODEREF for $state handler";
        }
      }
                                        # object states
      if (ref($handler) eq '') {
        $self->register_state($handler, $state);
        next;
      }
      if (ref($handler) ne 'ARRAY') {
        croak "strange reference ($handler) used as an object session method";
      }
      foreach my $method (@$handler) {
        $self->register_state($method, $state);
      }
    }
    else {
      last;
    }
  }

  if (@states) {
    croak "odd number of events/handlers (missing one or the other?)";
  }

  if (exists $self->[SE_STATES]->{'_start'}) {
    $POE::Kernel::poe_kernel->session_alloc($self, @args);
  }
  else {
    carp "discarding session $self - no '_start' state";
  }

  $self;
}

#------------------------------------------------------------------------------

sub create {
  my ($type, @params) = @_;
  my @args;

  croak "$type requires a working Kernel"
    unless (defined $POE::Kernel::poe_kernel);

  if (@params & 1) {
    croak "odd number of events/handlers (missin one or the other?)";
  }

  my %params = @params;

  my $self = bless { 'namespace' => { },
                     'options'   => { },
                   }, $type;

  if (exists $params{'args'}) {
    if (ref($params{'args'}) eq 'ARRAY') {
      push @args, @{$params{'args'}};
    }
    else {
      push @args, $params{'args'};
    }
    delete $params{'args'};
  }

  my @params_keys = keys(%params);
  foreach (@params_keys) {
    my $state_hash = $params{$_};

    croak "$_ does not refer to a hashref"
      unless (ref($state_hash) eq 'HASH');

    if ($_ eq 'inline_states') {
      while (my ($state, $handler) = each(%$state_hash)) {
        croak "inline state '$state' needs a CODE reference"
          unless (ref($handler) eq 'CODE');
        $self->register_state($state, $handler);
      }
    }
    elsif ($_ eq 'package_states') {
      while (my ($state, $handler) = each(%$state_hash)) {
        croak "states for package '$state' needs an ARRAY reference"
          unless (ref($handler) eq 'ARRAY');
        foreach my $method (@$handler) {
          $self->register_state($method, $state);
        }
      }
    }
    elsif ($_ eq 'object_states') {
      while (my ($state, $handler) = each(%$state_hash)) {
        croak "states for object '$state' need an ARRAY reference"
          unless (ref($handler) eq 'ARRAY');
        foreach my $method (@$handler) {
          $self->register_state($method, $state);
        }
      }
    }
    else {
      croak "unknown $type parameter: $_";
    }
  }

  if (exists $self->[SE_STATES]->{'_start'}) {
    $POE::Kernel::poe_kernel->session_alloc($self, @args);
  }
  else {
    carp "discarding session $self - no '_start' state";
  }

  $self;
}

#------------------------------------------------------------------------------

sub DESTROY {
  my $self = shift;
  # -><- clean out things
}

#------------------------------------------------------------------------------

sub _invoke_state {
  my ($self, $source_session, $state, $etc) = @_;

  if (exists($self->[SE_OPTIONS]->{'trace'})) {
    warn "$self -> $state\n";
  }

  if (exists $self->[SE_STATES]->{$state}) {
                                        # inline
    if (ref($self->[SE_STATES]->{$state}) eq 'CODE') {
      return &{$self->[SE_STATES]->{$state}}(undef,                   # object
                                            $self,                    # session
                                            $POE::Kernel::poe_kernel, # kernel
                                            $self->[SE_NAMESPACE],    # heap
                                            $state,                   # state
                                            $source_session,          # sender
                                            @$etc                     # args
                                           );
    }
                                        # package and object
    else {
      return
        $self->[SE_STATES]->{$state}->$state(                         # object
                                            $self,                    # session
                                            $POE::Kernel::poe_kernel, # kernel
                                            $self->[SE_NAMESPACE],    # heap
                                            $state,                   # state
                                            $source_session,          # sender
                                            @$etc                     # args
                                           );
    }
  }
                                        # recursive, so it does the right thing
  elsif (exists $self->[SE_STATES]->{'_default'}) {
    return $self->_invoke_state( $source_session,
                                 '_default',
                                 [ $state, $etc ]
                               );
  }
                                        # whoops!  no _default?
  else {
    $! = ENOSYS;
    if (exists $self->[SE_OPTIONS]->{'default'}) {
      warn "\t$self -> $state does not exist (and no _default)\n";
    }
    return undef;
  }

  return 0;
}

#------------------------------------------------------------------------------

sub register_state {
  my ($self, $state, $handler) = @_;

  if ($handler) {
    if (ref($handler) eq 'CODE') {
      carp "redefining state($state) for session($self)"
        if ( (exists $self->[SE_OPTIONS]->{'debug'}) &&
             (exists $self->[SE_STATES]->{$state})
           );
      $self->[SE_STATES]->{$state} = $handler;
    }
    elsif ($handler->can($state)) {
      carp "redefining state($state) for session($self)"
        if ( (exists $self->[SE_OPTIONS]->{'debug'}) &&
             (exists $self->[SE_STATES]->{$state})
           );
      $self->[SE_STATES]->{$state} = $handler;
    }
    else {
      if (ref($handler) eq 'CODE' &&
          exists($self->[SE_OPTIONS]->{'trace'})
      ) {
        carp "$self : state($state) is not a proper ref - not registered"
      }
      else {
        croak "object $handler does not have a '$state' method"
          unless ($handler->can($state));
      }
    }
  }
  else {
    delete $self->[SE_STATES]->{$state};
  }
}

#------------------------------------------------------------------------------

sub option {
  my $self = shift;
  push(@_, 0) if (scalar(@_) & 1);
  my %parameters = @_;

  while (my ($flag, $value) = each(%parameters)) {
                                        # booleanize some handy aliases
    ($value = 1) if ($value =~ /^(on|yes)$/i);
    ($value = 0) if ($value =~ /^(no|off)$/i);
                                        # set or clear the option
    if ($value) {
      $self->[SE_OPTIONS]->{lc($flag)} = $value;
    }
    else {
      delete $self->[SE_OPTIONS]->{lc($flag)};
    }
  }
}

###############################################################################
1;

__END__

#------------------------------------------------------------------------------
# Enqueue an event.

name is public
_name is friend
__name is private

sub _enqueue_event {
  my ($self, $sender, $state, $priority, $time, $etc) = @_;

  # Place the event is the session's queue.

  #
  # If "concurrent" POE:
  #   Start or unblock the session's dispatch thread.
  # End
  #
  # Return the number of events in the session's queues.

}

sub _dispatch_event {
  my ($self) = @_;

  # If "concurrent" POE:
  #   Return 1 if there are no events but the session has resources to keep it active.
  #   Return 0 if there are no events and the session is "stalled".
  # Otherwise, "regular" POE:
  #   Dispatch an event, and return the number of events left in the queue.
  # End
}

