# Copyright 1999-2000 Jesse Vincent <jesse@fsck.com>
# Released under the terms of the GNU Public License
# $Id$ 
#
#
package RT::Transaction;
use RT::Record;
@ISA= qw(RT::Record);

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = {};
  bless ($self, $class);

  $self->{'table'} = "Transactions";
  $self->_Init(@_);


  return ($self);
}

sub _Accessible {
  my $self = shift;
  my %Cols = (
	      TimeTaken => 'read',
	      Ticket => 'read',
	      Type=> 'read',
	      Data => 'read',
	      EffectiveTicket => 'read',
	      Creator => 'read',
	      Created => 'read'
	     );
}


#This is "Create Transaction"
sub Create {
  my $self = shift;
  
  my %args = ( id => undef,
	       TimeTaken => 0,
	       Ticket => 0 ,
               Type => '',
	       Data => '',
	       Field => undef,
	       OldValue => undef,
	       NewValue => undef,
	       @_
	     );
  #if we didn't specify a ticket, we need to bail
  if ( $args{'Ticket'} == 0) {
    return(0, "RT::Transaction->Create couldn't, as you didn't specify a ticket id");
  }
  
  #lets create our parent object
  my $id = $self->SUPER::Create(Ticket => $args{'Ticket'},
				EffectiveTicket  => $args{'Ticket'},
				TimeTaken => $args{'TimeTaken'},
				Type => $args{'Type'},
				Data => $args{'Data'},
				Field => $args{'Field'},
				OldValue => $args{'OldValue'},
				NewValue => $args{'NewValue'},
				Created => undef
			       );
  $self->Load($id);

  #We're really going to need a non-acled ticket for the scrips to work
  use RT::Ticket;
  #TODO this MUST be as the "System" principal or it all breaks
  #TODO This is actively broken, but it'll work as long as we have no acls
  my $TicketAsSystem = RT::Ticket->new($self->CurrentUser);
  $TicketAsSystem->Load($self->Ticket);

  #Load a scrips object
  use RT::Scrips;
  my $Scrips = RT::Scrips->new($self->CurrentUser);
  $Scrips->LimitToQueue($TicketAsSystem->Queue->Id); #Limit it to queue 0 or $Ticket->QueueId
  $Scrips->LimitToType($args{'Type'}); #Limit to $args{'Type'} or 'any'
  #Load a scrips object
  #Iterate through each script and check it's applicability.

  #Tobias: Why is this needed?  -- jesse
  $args{'TicketObject'}=$TicketAsSystem;

  
  while (my $Scrip = $Scrips->Next()) {
    
    #Load the scrip's action;
    $Scrip->LoadAction(TicketObject=>$TicketAsSystem, TransactionObject=>$self);

    #If it's applicable, prepare and commit it
    if ( $Scrip->IsApplicable() ) {
      
      $Scrip->Prepare();
      $Scrip->Commit();
    }
    
  } 
  
  return ($id, "Transaction Created");
}


sub CreatedAsString {
  my $self = shift;
  return($self->_Value('Created'));
}


sub Message {
 my $self = shift;
  
  use RT::Attachments;
 if (!defined ($self->{'message'}) ){
   
   $self->{'message'} = new RT::Attachments($self->CurrentUser);
   $self->{'message'}->Limit(FIELD => 'TransactionId',
			     VALUE => $self->Id);

   $self->{'message'}->ChildrenOf(0);
 } 
 return($self->{'message'});
}

sub Attachments {
  my $self = shift;
  if (@_) {
    my $Types = shift;
  }
  
  #TODO cache this
  use RT::Attachments;
  my $Attachments = new RT::Attachments($self->CurrentUser);
  $Attachments->Limit(FIELD => 'TransactionId',
		      VALUE => $self->Id);

  if ($Types) {
    $Attachments->Limit(FIELD => 'ContentType',
			VALUE => "%$Types%",
			OPERATOR => "LIKE");
  }
  
  
  return($Attachments);

}
sub Attach {
  my $self = shift;
  my $MIMEObject = shift;

  if (!defined($MIMEObject)) {
    die "RT::Transaction->Attach: We can't attach a mime object if you don't give us one.\n";
  }
  

  use RT::Attachment;
  my $Attachment = new RT::Attachment ($self->CurrentUser);
  $Attachment->Create(TransactionId => $self->Id,
		      Attachment => $MIMEObject);
  return ($Attachment, "Attachment created");
  
}



sub Description {
  my $self = shift;
  if (!defined($self->Type)) {
    return("No transaction type specified");
  }
  if ($self->Type eq 'Create'){
    return("Request created by ".$self->Creator->UserId);
  }
  elsif ($self->Type eq 'Set') {
    if ($self->Field eq 'Owner') {
      return ("Owner changed from " . $self->OldValue ." to ".$self->NewValue ." by ". $self->Creator->UserId);
    }

    #TODO Add the other Set types here.
  }

  elsif ($self->Type eq 'Ccorrespond')    {
    return("Mail sent by ". $self->Creator->UserId);
  }
  
  elsif ($self->Type eq 'Comment')  {
    return( "Comments added by ".$self->Creator->UserId);
  }
  
  elsif ($self->Type eq 'area')  {
    my $to = $self->{'data'};
    $to = 'none' if ! $to;
    return( "Area changed to $to by". $self->Creator->UserId);
  }
  
  elsif ($self->Type eq 'status'){
    if ($self->Data eq 'dead') {
      return ("Request killed by ". $self->Creator->UserId);
    }
    else {
      return( "Status changed to ".$self->Data." by ".$self->Creator->UserId);
    }
  }
  elsif ($self->Type eq 'queue_id'){
    return( "Queue changed to ".$self->Data." by ".$self->Creator->UserId);
  }
  elsif ($self->Type eq 'owner'){
    if ($self->Data eq $self->Creator->UserId){
      return( "Taken by ".$self->Creator->UserId);
    }
    elsif ($self->Data eq ''){
      return( "Untaken by ".$self->Creator->UserId);
    }
    
    else{
      return( "Owner changed to ".$self->Data." by ". $self->Creator->UserId);
    }
  }
  elsif ($self->Type eq 'requestors'){
    return( "User changed to ".$self->Data." by ".$self->Creator->UserId);
  }
  elsif ($self->Type eq 'priority') {
    return( "Priority changed to ".$self->Data." by ".$self->Creator->UserId);
      }    
  elsif ($self->Type eq 'final_priority') {
    return( "Final Priority changed to ".$self->Data." by ".$self->Creator->UserId);
      }
  elsif ($self->Type eq 'date_due') {  
    ($wday, $mon, $mday, $hour, $min, $sec, $TZ, $year)=&parse_time(".$self->Data.");
      $text_time = sprintf ("%s, %s %s %4d %.2d:%.2d:%.2d", $wday, $mon, $mday, $year,$hour,$min,$sec);
    return( "Date Due changed to $text_time by ".$self->Creator->UserId);
    }
  elsif ($self->Type eq 'Subject') {
      return( "Subject changed to ".$self->Data." by ".$self->Creator->UserId);
      }
  elsif ($self->Type eq 'date_told') {
    return( "User notified by ".$self->Creator->UserId);
      }
  elsif ($self->Type eq 'effective_sn') {
    return( "Request $self->{'serial_num'} merged into ".$self->Data." by ".$self->Creator->UserId);
  }
  elsif ($self->Type eq 'subreqrsv') {
    return "Subrequest #".$self->Data." resolved by ".$self->Creator->UserId;
  }
  elsif ($self->Type eq 'link') {
    #TODO: make this fit with the rest of things.
    
    #my ($db, $fid, $type, $remote)=split(/\/, $self->{'data'});
    if ($type =~ /^dependency(-?)$/) {
      #$remote=(defined $remote) ? " at $remote" : "";
      if ($1 eq '-') {
	return ("Request \#$fid$remote made dependent on this request by ".$self->Creator->UserId);
      } else {
	return ("This request made dependent on request \#$fid$remote by ".$self->Creator->UserId);
      }
    } else {
      
      # Some kind of plugin system needed here.
      
      return ("$type linked to $fid at $remote by ".$self->Creator->UserId);
    }
  }
  else {
    return($self->Type . " modified. RT Should be more explicit about this!");
  }
  
  
}
#ACCESS CONTROL
# 
sub DisplayPermitted {
  my $self = shift;

  my $actor = shift;
  if (!$actor) {
    my $actor = $self->CurrentUser->Id();
  }
  if (1) {
#  if ($self->Queue->DisplayPermitted($actor)) {
    return(1);
  }
  else {
    #if it's not permitted,
    return(0);
  }
}

sub ModifyPermitted {
  my $self = shift;
  my $actor = shift;
  if (!$actor) {
    my $actor = $self->CurrentUser->Id();
  }
  if ($self->Queue->ModifyPermitted($actor)) {
    
    return(1);
  }
  else {
    #if it's not permitted,
    return(0);
  }
}

sub AdminPermitted {
  my $self = shift;
  my $actor = shift;
  if (!$actor) {
    my $actor = $self->CurrentUser->Id();
  }


  if ($self->Queue->AdminPermitted($actor)) {
    
    return(1);
  }
  else {
    #if it's not permitted,
    return(0);
  }
}
1;
