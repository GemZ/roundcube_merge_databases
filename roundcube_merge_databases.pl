#!/usr/bin/perl

# This Script is barely tested! Backup your DBs!
#
# Reads users from roundcube DB and writes them with the
# associated contacts to another existing roundcube DB
# Author: Alexander Friess 06-02-2016

use strict;
use warnings;

use Getopt::Long;
use DBI;

  my $opts;
  GetOptions(
      'help|h!'            => \$opts->{Help},
      'source-host|host=s' => \$opts->{SourceHost},
      'target-host=s'      => \$opts->{TargetHost},
      'source-db|db=s'     => \$opts->{SourceDb},
      'target-db=s'        => \$opts->{TargetDb},
      'source-user|user=s' => \$opts->{SourceUser},
      'source-pass|pass=s' => \$opts->{SourcePass},
  ) or die();

  if ( !$opts->{SourceHost} ) { $opts->{SourceHost} = "localhost"; }
  if ( !$opts->{TargetHost} ) { $opts->{TargetHost} = $opts->{SourceHost}; }
  if ( !$opts->{SourceDb} ) { $opts->{SourceDb} = "roundcube"; }
  if ( !$opts->{TargetDb} ) { $opts->{TargetDb} = $opts->{SourceDb}; }
  if ( !$opts->{SourceUser} ) { $opts->{SourceUser} = "roundcube"; }
  if ( !$opts->{TargetUser} ) { $opts->{TargetUser} = $opts->{SourceUser}; }
  if ( $opts->{SourceHost} eq $opts->{TargetHost} && $opts->{SourceDb} eq $opts->{TargetDb} ) { die "TargetDB == SourceDB"; }

  my $dsn_source = "DBI:mysql:host=$opts->{SourceHost};database=$opts->{SourceDb};port=3306;user=$opts->{SourceUser};password=$opts->{SourcePass}";
  my $dbh_source = DBI->connect( $dsn_source, { RaiseError => 0, PrintError => 0, } );
  my $dsn_target;
  my $dbh_target;

  if ( !$dbh_source ) { die("Could not connect to Source DB!\n"); }
  else { print "Connected to Source DB\n"; }

  if ( $opts->{SourceHost} ne $opts->{TargetHost} ) {
    $dsn_target = "DBI:mysql:host=$opts->{TargetHost};database=$opts->{TargetDb};port=3306;user=roundcube;password=roundcube";
    $dbh_target = DBI->connect( $dsn_target, { RaiseError => 0, PrintError => 0, } );

    if ( !$dbh_target ) { die("Could not connect to Target DB!\n"); }
    else { print "Connected to Target DB\n"; }
  }
  else {
    $dbh_target = $dbh_source;
  }

  my $sql_users = 'SELECT * FROM `' . $opts->{SourceDb} . '`.users';
  #if mailhost dann cat where ?
  my $sth_users = $dbh_source->prepare($sql_users);

  my $sql_new_user = 'INSERT INTO `' . $opts->{TargetDb} . '`.users (username,mail_host,alias,created,last_login,language,preferences) VALUES(?,?,?,?,?,?,?)';
  my $sth_new_user = $dbh_target->prepare($sql_new_user);

  my $sql_contacts = 'SELECT * FROM `' . $opts->{SourceDb} . '`.contacts WHERE user_id = ?';
  my $sth_contacts = $dbh_source->prepare($sql_contacts);

  my $sql_new_contact = 'INSERT INTO `' . $opts->{TargetDb} . '`.contacts (changed,del,name,email,firstname,surname,vcard,words,user_id) VALUES(?,?,?,?,?,?,?,?,?)';
  my $sth_new_contact = $dbh_target->prepare($sql_new_contact);

  #Read Source Users:
  $sth_users->execute();
  while ( my ( $old_user_id, $username, $mailhost, $alias, $created, $last_login, $language, $preferences ) = $sth_users->fetchrow_array() ) {

    #Insert new User:
    if ( !$sth_new_user->execute( $username, $mailhost, $alias, $created, $last_login, $language, $preferences ) ) {
      warn( "Could not execute Query $sql_new_user: " . $sth_new_user->errstr );
      next;
    }

    my $new_user_id = $sth_new_user->{mysql_insertid};
    print "Copied: $username\n";

    #Read associated Contacts of User:
    $sth_contacts->execute($old_user_id);
    while ( my ( $old_contact_id, $changed, $del, $name, $email, $firstname, $surname, $vcard, $words, $c_user_id ) = $sth_contacts->fetchrow_array() ) {

      #Insert new Contact:
      if ( !$sth_new_contact->execute( $changed, $del, $name, $email, $firstname, $surname, $vcard, $words, $new_user_id ) ) {
        warn( "Could not execute Query $sql_new_contact " . $sth_new_contact->errstr );
        next;
      }
      print "  Contact: $name\n";
      $sth_new_contact->finish();
    }

  $sth_new_user->finish();
  }

$dbh_source->disconnect();
$dbh_target->disconnect();

