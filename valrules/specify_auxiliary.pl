#!/usr/bin/perl -wT

use strict;
use utf8;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use File::Basename;
use JSON::Parse 'json_file_to_perl';
use YAML qw(LoadFile);
#binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use open ':utf8';
use Encode;
use charnames ();

# Path to the data on the web server.
my $path = '/home/zeman/unidep/docs-automation/valrules';
# Read the list of known languages.
my $languages = LoadFile('/home/zeman/unidep/docs-automation/codes_and_flags.yaml');
if ( !defined($languages) )
{
    die "Cannot read the list of languages";
}
# The $languages hash is indexed by language names. Create a mapping from language codes.
# At the same time, separate family from genus where applicable.
my %lname_by_code; map {$lname_by_code{$languages->{$_}{lcode}} = $_} (keys(%{$languages}));
foreach my $lname (keys(%{$languages}))
{
    $lname_by_code{$languages->{$lname}{lcode}} = $lname;
    my $family_genus = $languages->{$lname}{family};
    if($family_genus =~ m/^(.+),\s*(.+)$/)
    {
        $languages->{$lname}{familygenus} = $family_genus;
        $languages->{$lname}{family} = $1;
        $languages->{$lname}{genus} = $2;
    }
    else
    {
        $languages->{$lname}{familygenus} = $family_genus;
        $languages->{$lname}{genus} = '';
    }
    $languages->{$lname}{family} = 'Indo-European' if($languages->{$lname}{family} eq 'IE');
}
my @functions =
(
    ['Copula (tagged AUX)', 'cop.AUX'],
    ['Copula (tagged PRON/DET)', 'cop.PRON'],
    ['Periphrastic aspect: perfect', 'Aspect=Perf'],
    ['Periphrastic aspect: progressive', 'Aspect=Prog'],
    ['Periphrastic tense: past', 'Tense=Past'],
    ['Periphrastic tense: present', 'Tense=Pres'],
    ['Periphrastic tense: future', 'Tense=Fut'],
    ['Periphrastic voice: passive', 'Voice=Pass'],
    ['Periphrastic voice: causative', 'Voice=Cau'],
    ['Periphrastic mood: conditional', 'Mood=Cnd'],
    ['Periphrastic mood: imperative', 'Mood=Imp'],
    ['Needed in negative clauses (like English “do”, not like “not”)', 'neg'],
    ['Needed in interrogative clauses (like English “do”)', 'int'],
    ['Modal auxiliary: necessitative (“must, should”)', 'Mood=Nec'],
    ['Modal auxiliary: potential (“can, might”)', 'Mood=Pot'],
    ['Modal auxiliary: desiderative (“want”)', 'Mood=Des']
);
# We must set our own PATH even if we do not depend on it.
# The system call may potentially use it, and the one from outside is considered insecure.
$ENV{'PATH'} = $path.':/home/zeman/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';
# Print the output.
my $query = new CGI;
my $remoteaddr = $query->remote_addr();
# The traffic is being forwarded through quest, so normally we see quest's local address as the remote address.
# Let's see if we have the real remote address in the environment.
if ( exists($ENV{HTTP_X_FORWARDED_FOR}) && $ENV{HTTP_X_FORWARDED_FOR} =~ m/^(\d+\.\d+\.\d+\.\d+)$/ )
{
    $remoteaddr = $1;
}
my %config = get_parameters($query, \%lname_by_code, \@functions);
$query->charset('utf-8'); # makes the charset explicitly appear in the headers
print($query->header());
print <<EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <title>Specify auxiliaries in UD</title>
  <style type="text/css">
    img {border: none;}
    img.flag {
      vertical-align: middle;
      border: solid grey 1px;
      height: 1em;
    }
  </style>
</head>
<body>
EOF
;
#------------------------------------------------------------------------------
# If there were low-level errors in the parameters, print the error messages
# and exit.
if(scalar(@{$config{errors}}) > 0)
{
    print("<h1>Error in parameters:</h1>\n");
    foreach my $error (@{$config{errors}})
    {
        print("<p>".htmlescape($error)."</p>\n");
    }
}
#------------------------------------------------------------------------------
# No language code specified. Show the list of known languages.
elsif($config{lcode} eq '')
{
    print("  <h1>Specify auxiliaries for a language</h1>\n");
    # Print the list of known languages.
    print("  <p><strong>Select a language:</strong></p>\n");
    print("  <table>\n");
    my %families; map {$families{$languages->{$_}{family}}++} (keys(%{$languages}));
    my @familylines;
    foreach my $family (sort(keys(%families)))
    {
        print("  <tr><td>$family:</td><td>");
        my @lnames = sort(grep {$languages->{$_}{family} eq $family} (keys(%{$languages})));
        print(join(', ', map {"<span style='white-space:nowrap'><img class=\"flag\" src=\"https://universaldependencies.org/flags/png/$languages->{$_}{flag}.png\" /> <a href=\"specify_auxiliary.pl?lcode=$languages->{$_}{lcode}\">$_</a></span>"} (@lnames)));
        print("</td></tr>\n");
    }
    print("  </table>\n");
}
#------------------------------------------------------------------------------
# Language code specified. We can edit auxiliaries of that language.
else
{
    # Read the data file, either from the old Python list, or from JSON.
    my %data;
    if(0)
    {
        %data = read_auxiliaries_from_python();
    }
    else
    {
        %data = read_data_json(\@functions); ###!!! we only need \@functions a single time there
    }
    # Check whether there are any undocumented auxiliaries. Documenting them
    # has higher priority than any other action the user may want to do.
    my $n_undocumented = 0;
    # It is possible that there are no auxiliaries for my language so far.
    if(exists($data{$config{lcode}}))
    {
        my $auxiliaries = $data{$config{lcode}};
        $n_undocumented = scalar(grep {$auxiliaries->{$_}{status} ne 'documented'} (keys(%{$auxiliaries})));
    }
    # Perform an action according to the CGI parameters.
    # Saving may be needed even for documenting undocumented auxiliaries.
    if($config{save})
    {
        process_form_data(\%data);
    }
    # If we are not saving but have received a lemma, it means the lemma should be edited.
    # This may also be needed for documenting undocumented auxiliaries.
    elsif($config{lemma} ne '')
    {
        summarize_guidelines();
        print_lemma_form(\%data);
        print_all_auxiliaries(\%data);
    }
    # Now if there are any undocumented auxiliaries, offer documenting them as the only possible action.
    elsif($n_undocumented > 0)
    {
        summarize_guidelines();
        print_undocumented_auxiliaries(\%data);
        print_all_auxiliaries(\%data);
    }
    elsif($config{add}) # addcop and addnoncop will be used inside print_lemma_form()
    {
        summarize_guidelines();
        print_lemma_form(\%data);
        print_all_auxiliaries(\%data);
    }
    else
    {
        summarize_guidelines();
        print_edit_add_menu(\%data);
        # Show all known auxiliaries so the user can compare. This and related languages first.
        print_all_auxiliaries(\%data);
    }
}
print <<EOF
</body>
</html>
EOF
;



#------------------------------------------------------------------------------
# Prints the list of undocumented auxiliaries.
#------------------------------------------------------------------------------
sub print_undocumented_auxiliaries
{
    my $data = shift;
    my %auxiliaries = %{$data->{$config{lcode}}};
    my @undocumented = sort(grep {$auxiliaries{$_}{status} ne 'documented'} (keys(%auxiliaries)));
    my $n = scalar(@undocumented);
    if($n > 0)
    {
        my $hrefs = get_lemma_links_to_edit(@undocumented);
        # Already documented auxiliaries should stay available for editing while
        # the rest is being documented (e.g. the user may want to return to a
        # copula and explain its deficient paradigm if they find they have forgotten it).
        # The only thing we will hide until all auxiliaries are documented is the Add new button.
        my @documented = sort(grep {$auxiliaries{$_}{status} eq 'documented'} (keys(%auxiliaries)));
        if(scalar(@documented) > 0)
        {
            $hrefs .= ' | Already documented: '.get_lemma_links_to_edit(@documented);
        }
        print("  <h2 style='color:red'>You have $n undocumented auxiliaries!</h2>\n");
        print("  <p>Please edit each undocumented auxiliary and supply the missing information.</p>\n");
        print("  <p>$hrefs</p>\n");
    }
}



#------------------------------------------------------------------------------
# Prints the list of documented auxiliaries for editing and the button to add
# a new auxiliary.
#------------------------------------------------------------------------------
sub print_edit_add_menu
{
    my $data = shift;
    print("  <h2>Edit or add auxiliaries</h2>\n");
    my @ndcop = ();
    if(exists($data->{$config{lcode}}))
    {
        my @lemmas = sort(keys(%{$data->{$config{lcode}}}));
        my $hrefs = get_lemma_links_to_edit(@lemmas);
        print("  <p>$hrefs</p>\n");
        # Do not offer adding a copula if there already is a copula without documented deficient paradigm.
        @ndcop = grep {$data->{$config{lcode}}{$_}{function} =~ m/^cop\./ && $data->{$config{lcode}}{$_}{deficient} eq ''} (@lemmas);
    }
    print("  <form action=\"specify_auxiliary.pl\" method=\"post\" enctype=\"multipart/form-data\">\n");
    print("    <input name=lcode type=hidden value=\"$config{lcode}\" />\n");
    print("    <input name=ghu type=hidden value=\"$config{ghu}\" />\n");
    if(scalar(@ndcop)==0)
    {
        print("    <input name=add type=submit value=\"Add copula\" />\n");
        print("    <input name=add type=submit value=\"Add other\" />\n");
    }
    else
    {
        print("    The copula has been specified <i>(".join(', ', @ndcop).")</i>.\n");
        print("    <input name=add type=submit value=\"Add non-copula\" />\n");
    }
    print("  </form>\n");
}



#------------------------------------------------------------------------------
# Returns a list of lemmas as HTML links to the edit form.
#------------------------------------------------------------------------------
sub get_lemma_links_to_edit
{
    my @lemmas = @_;
    my @hrefs;
    foreach my $lemma0 (@lemmas)
    {
        # For a safe URL we assume that the lemma contains only letters. That should not be a problem normally.
        # We must also allow the hyphen, needed in Skolt Sami "i-ǥõl". (Jack Rueter: It is written with a hyphen. Historically it might be traced to a combination of the AUX:NEG ij and a reduced ǥõl stem derived from what is now the verb õlggâd ʹhave toʹ. The word-initial g has been retained in the fossilized contraction as ǥ, but that same word-initial letter has been lost in the standard verb.)
        # We must also allow the apostrophe, needed in Mbya Guarani "nda'ei" and "nda'ipoi".
        my $lemma = $lemma0;
        $lemma =~ s/[^-\pL\pM']//g; #'
        my $alert = '';
        if($lemma ne $lemma0)
        {
            $alert = " <span style='color:red'>ERROR: Lemma must consist only of letters but stripping non-letters from '".htmlescape($lemma0)."' yields '$lemma'!</span>";
        }
        my $href = "<a href=\"specify_auxiliary.pl?ghu=$config{ghu}&amp;lcode=$config{lcode}&amp;lemma=$lemma\">$lemma</a>$alert";
        push(@hrefs, $href);
    }
    return join(' ', @hrefs);
}



#------------------------------------------------------------------------------
# Prints the form where a particular lemma can be edited.
#------------------------------------------------------------------------------
sub print_lemma_form
{
    my $data = shift;
    # This function can be called for an empty lemma, in which case we want to
    # add a new auxiliary. However, if the lemma is non-empty, it must be
    # known.
    my $record;
    if($config{lemma} eq '')
    {
        $record =
        {
            'function'  => '',
            'rule'      => '',
            'deficient' => '',
            'example'   => '',
            'exampleen' => '',
            'comment'   => '',
            'status'    => 'new'
        };
    }
    elsif(exists($data->{$config{lcode}}{$config{lemma}}))
    {
        $record = $data->{$config{lcode}}{$config{lemma}};
    }
    else
    {
        die("Lemma '$config{lemma}' not found in language '$config{lcode}'");
    }
    my $hrule = htmlescape($record->{rule});
    my $hdeficient = htmlescape($record->{deficient});
    my $hexample = htmlescape($record->{example});
    my $hexampleen = htmlescape($record->{exampleen});
    my $hcomment = htmlescape($record->{comment});
    print <<EOF
  <form action="specify_auxiliary.pl" method="post" enctype="multipart/form-data">
  <input name=lcode type=hidden value="$config{lcode}" />
  <p>Please tell us your Github user name:
    <input name=ghu type=text value="$config{ghu}" />
    Are you a robot? (one word) <input name=smartquestion type=text size=10 /><br />
    <small>Your edits will be ultimately propagated to UD Github repositories
    and we need to be able to link them to a particular user if there are any
    issues to be discussed. This is not a problem when you edit directly on
    Github, but here the actual push action will be formally done by another
    user.</small></p>
  <table>
    <tr>
      <td>Lemma</td>
      <td>Function</td>
      <td>Rule</td>
EOF
    ;
    # If we are adding or editing a copula, add a field where multiple copulas can be justified.
    # This field should also be available if we are documenting a previously undocumented
    # auxiliary, which could be a copula.
    if($config{addcop} || $record->{function} =~ m/^cop\./ || $record->{status} eq 'undocumented')
    {
        print("      <td>Deficient paradigm</td>\n");
    }
    print("      <td>Example</td>\n");
    unless($config{lcode} eq 'en')
    {
        print("      <td>English translation of the example</td>\n");
    }
    print <<EOF
      <td>Comment</td>
    </tr>
EOF
    ;
    print("    <tr>\n");
    print("      <td>");
    if($config{lemma} ne '')
    {
        print("<strong>$config{lemma}</strong><input name=lemma type=hidden size=10 value=\"$config{lemma}\" />");
    }
    else
    {
        print("<input name=lemma type=text size=10 />");
    }
    print("</td>\n");
    # If we are adding or editing a copula, the function is restricted.
    if($config{addcop} || $record->{function} =~ m/^cop\./)
    {
        print("      <td>\n");
        print("        <select name=function>\n");
        foreach my $f (@functions)
        {
            next if($f->[1] !~ m/^cop\./);
            my $selected = '';
            if($f->[1] eq $record->{function})
            {
                $selected = ' selected';
            }
            print("          <option value=\"$f->[1]\"$selected>".htmlescape($f->[0])."</option>\n");
        }
        print("        </select>\n");
        print("      </td>\n");
        print("      <td>combination of the copula and a nonverbal predicate<input name=rule type=hidden value=\"combination of the copula and a nonverbal predicate\" /></td>\n");
    }
    else
    {
        print("      <td>\n");
        print("        <select name=function>\n");
        print("          <option>-----</option>\n");
        foreach my $f (@functions)
        {
            # The Copula functions should be available if we are documenting an undocumented auxiliary.
            # Otherwise it is not available because we must use 'addcop', see above.
            next if($f->[1] =~ m/^cop\./ && $record->{status} ne 'undocumented');
            my $selected = '';
            if($f->[1] eq $record->{function})
            {
                $selected = ' selected';
            }
            print("          <option value=\"$f->[1]\"$selected>".htmlescape($f->[0])."</option>\n");
        }
        print("        </select>\n");
        print("      </td>\n");
        print("      <td><input name=rule type=text size=30 value=\"$hrule\" /></td>\n");
    }
    if($config{addcop} || $record->{function} =~ m/^cop\./ || $record->{status} eq 'undocumented')
    {
        print("      <td><input name=deficient type=text size=30 value=\"$hdeficient\" /></td>\n");
    }
    print("      <td><input name=example type=text size=30 value=\"$hexample\" /></td>\n");
    unless($config{lcode} eq 'en')
    {
        print("      <td><input name=exampleen type=text size=30 value=\"$hexampleen\" /></td>\n");
    }
    print("      <td><input name=comment type=text value=\"$hcomment\" /></td>\n");
    print("    </tr>\n");
    print("    <tr>\n");
    # If we are adding a new lemma, we will have to check that it is really new.
    # Signal that with a slightly different button text, "Save new" instead of "Save".
    if($config{add})
    {
        print("      <td><input name=save type=submit value=\"Save new\" /></td>\n");
    }
    else
    {
        print("      <td><input name=save type=submit value=\"Save\" /></td>\n");
    }
    # Do not print the hint for the function/rule if the function/rule is fixed (copula).
    # But do print the hint for multiple copulas.
    if($config{addcop} || $record->{function} =~ m/^cop\./)
    {
        print("      <td></td>\n");
        print("      <td></td>\n");
    }
    else
    {
        print("      <td><small>Missing function that conforms to the guidelines? Contact Dan!</small></td>\n");
        print("      <td><small>E.g. “combination of the auxiliary and a past participle of the main verb”</small></td>\n");
    }
    if($config{addcop} || $record->{function} =~ m/^cop\./ || $record->{status} eq 'undocumented')
    {
        print("      <td><small>If you want multiple copulas, you must justify each, e.g. “used in past tense only”</small></td>\n");
    }
    print <<EOF
      <td><small>Mark the auxiliary by enclosing it in square brackets, e.g., “he [has] done it”</small></td>
      <!-- empty cells under english example and comment omitted (the one under english example would have to appear only if lcode is not en -->
    </tr>
  </table>
  </form>
EOF
    ;
}



#------------------------------------------------------------------------------
# Processes data submitted from a form and prints confirmation or an error
# message.
# We are processing a Save request after a lemma was edited.
# We have briefly checked that the parameters match expected regular expressions.
# Nevertheless, only now we can also report an error if a parameter is empty.
#------------------------------------------------------------------------------
sub process_form_data
{
    my $data = shift;
    my $error = 0;
    print("  <h2>This is a result of a Save button</h2>\n");
    print("  <ul>\n");
    if($config{ghu} ne '')
    {
        print("    <li>user = '$config{ghu}'</li>\n");
    }
    else
    {
        print("    <li style='color:red'>ERROR: Missing Github user name</li>\n");
        $error = 1;
    }
    if($config{smartquestion} eq 'no')
    {
        print("    <li>robot = '$config{smartquestion}'</li>\n");
    }
    else
    {
        print("    <li style='color:red'>ERROR: Unsatisfactory robotic response</li>\n");
        $error = 1;
    }
    if($config{lemma} ne '')
    {
        print("    <li>lemma = '$config{lemma}'</li>\n");
        if($config{savenew} && exists($data->{$config{lcode}}{$config{lemma}}))
        {
            print("    <li style='color:red'>ERROR: There already is an auxiliary with the lemma '$config{lemma}'. Instead of re-adding it, you should edit it</li>\n");
            $error = 1;
        }
    }
    else
    {
        print("    <li style='color:red'>ERROR: Missing lemma</li>\n");
        $error = 1;
    }
    if($config{function} ne '')
    {
        print("    <li>function = '".htmlescape($config{function})."'</li>\n");
    }
    else
    {
        print("    <li style='color:red'>ERROR: Missing function</li>\n");
        $error = 1;
    }
    if($config{rule} ne '')
    {
        print("    <li>rule = '".htmlescape($config{rule})."'</li>\n");
    }
    else
    {
        print("    <li style='color:red'>ERROR: Missing rule</li>\n");
        $error = 1;
    }
    # We will assess the obligatoriness of the 'deficient' parameter later.
    if($config{deficient} ne '')
    {
        print("    <li>deficient = '".htmlescape($config{deficient})."'</li>\n");
    }
    if($config{example} ne '')
    {
        print("    <li>example = '".htmlescape($config{example})."'</li>\n");
    }
    else
    {
        print("    <li style='color:red'>ERROR: Missing example</li>\n");
        $error = 1;
    }
    if($config{exampleen} ne '')
    {
        print("    <li>exampleen = '".htmlescape($config{exampleen})."'</li>\n");
    }
    elsif($config{lcode} ne 'en')
    {
        print("    <li style='color:red'>ERROR: Missing English translation of the example</li>\n");
        $error = 1;
    }
    if($config{comment} ne '')
    {
        print("    <li>comment = '".htmlescape($config{comment})."'</li>\n");
    }
    # Check whether there will be more than one copulas if we add this one to the data.
    # If there will, check that all of them (including the new one) have a distinct
    # explanation of its deficient paradigm.
    if($config{function} =~ m/^cop\./)
    {
        my %copjust;
        foreach my $lemma (keys(%{$data->{$config{lcode}}}))
        {
            if($data->{$config{lcode}}{$lemma}{function} =~ m/^cop\./)
            {
                $copjust{$lemma} = $data->{$config{lcode}}{$lemma}{deficient};
            }
        }
        $copjust{$config{lemma}} = $config{deficient};
        my $ok = 1;
        my @copulas = sort(keys(%copjust));
        my $n = scalar(@copulas);
        if($n > 1)
        {
            foreach my $lemma (@copulas)
            {
                if($copjust{$lemma} eq '')
                {
                    print("    <li style='color:red'>ERROR: Copula '$lemma' does not have a deficient paradigm, hence there cannot be $n copulas</li>\n");
                    $error = 1;
                }
                if($lemma ne $config{lemma} && $copjust{$lemma} eq $config{deficient})
                {
                    print("    <li style='color:red'>ERROR: Explanation of deficient paradigm '$config{deficient}' is identical to the explanation given for '$lemma'</li>\n");
                    $error = 1;
                }
            }
        }
    }
    print("  </ul>\n");
    if($error)
    {
        print("  <p style='color:red'><strong>WARNING:</strong> Nothing was saved because there were errors.</p>\n");
        print("  <p>TO DO: obligatoriness of deficient</p>\n");
    }
    else
    {
        # Create a new record. If we are adding a new auxiliary, this will be
        # its record. If we are editing an existing auxiliary, first copy the
        # old values from the old values, then replace the edited ones, then
        # replace the old record with the new one.
        ###!!! At present a deep copy is not needed because there are no nested structures.
        my %record;
        if(exists($data->{$config{lcode}}{$config{lemma}}))
        {
            %record = %{$data->{$config{lcode}}{$config{lemma}}};
        }
        # Do I want to use my local time or universal time in the timestamps?
        #my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime(time());
        my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = localtime(time());
        my $timestamp = sprintf("%04d-%02d-%02d-%02d-%02d-%02d", 1900+$year, 1+$mon, $mday, $hour, $min, $sec);
        $record{lastchanged} = $timestamp;
        $record{lastchanger} = $config{ghu};
        $record{function} = $config{function};
        $record{rule} = $config{rule};
        $record{deficient} = $config{deficient};
        $record{example} = $config{example};
        $record{exampleen} = $config{exampleen};
        $record{comment} = $config{comment};
        $record{status} = 'documented';
        $data->{$config{lcode}}{$config{lemma}} = \%record;
        write_data_json($data, "$path/data.json");
        # Commit the changes to the repository and push them to Github.
        system("/home/zeman/bin/git-push-docs-automation.sh '$config{ghu}' '$config{lcode}' > /dev/null");
        print <<EOF
  <form action="specify_auxiliary.pl" method="post" enctype="multipart/form-data">
    <input name=lcode type=hidden value="$config{lcode}" />
    <input name=ghu type=hidden value="$config{ghu}" />
    <input name=gotolang type=submit value="Return to list" />
  </form>
EOF
        ;
    }
}



#------------------------------------------------------------------------------
# Prints the initial warning that not everything is an auxiliary.
#------------------------------------------------------------------------------
sub summarize_guidelines
{
    print <<EOF
  <h1><img class=\"flag\" src=\"https://universaldependencies.org/flags/png/$languages->{$lname_by_code{$config{lcode}}}{flag}.png\" />
    Specify auxiliaries for $lname_by_code{$config{lcode}}</h1>
  <p><strong>Remember:</strong> Not everything that a traditional grammar labels
    as auxiliary is necessarily an <a href="https://universaldependencies.org/u/pos/AUX_.html">auxiliary in UD</a>.
    Just because a verb combines with another verb does not necessarily mean
    that one of the verbs is auxiliary; the usual alternative in UD is treating
    one of the verbs as an <tt><a href="https://universaldependencies.org/u/dep/xcomp.html">xcomp</a></tt>
    of the other, or in some languages as a serial verb construction
    (<tt><a href="https://universaldependencies.org/u/dep/compound.html">compound:svc</a></tt>).
    Language-specific tests whether a verb is auxiliary are
    grammatical rather than semantic: just because something has a modal or
    near-modal meaning does not mean that it is an auxiliary, and in some
    languages modal verbs do not count as auxiliaries at all. Some verbs
    function as auxiliaries in some constructions and as full verbs in others
    (e.g., <i>to have</i> in English). There are also auxiliaries whose nature
    is completely different from verbs in the given language.</p>
  <p><strong>Remember:</strong> A language typically has at most one lemma for
    <a href="https://universaldependencies.org/u/dep/cop.html">copula</a>.
    Exceptions include deficient paradigms (different present and past copula,
    positive and negative, imperfect and iterative), and also the Romance verbs
    <i>ser</i> and <i>estar</i> (both equivalents of “to be”). In contrast,
    equivalents of “to become, to stay, to look like, to be called” etc. are not copulas
    in UD, even if a traditional grammar classifies them as such. In UD they
    should head an <tt><a href="https://universaldependencies.org/u/dep/xcomp.html">xcomp</a></tt>
    relation instead. A copula is normally tagged <a href="https://universaldependencies.org/u/pos/AUX_.html">AUX</a>.
    Exception: in some languages a personal or demonstrative pronoun /
    determiner can be used as a copula and then we keep it tagged
    <a href="https://universaldependencies.org/u/pos/PRON.html">PRON</a> or
    <a href="https://universaldependencies.org/u/pos/DET.html">DET</a>.</p>
EOF
    ;
}



#------------------------------------------------------------------------------
# Prints auxiliaries of all languages, this and related languages first.
#------------------------------------------------------------------------------
sub print_all_auxiliaries
{
    my $data = shift;
    # Print the data on the web page.
    print("  <h2>Known auxiliaries for this and other languages</h2>\n");
    # First display the actual language.
    # Then display languages from the same family and genus.
    # Then languages from the same family but different genera.
    # Then all remaining languages.
    # Hash families and genera for language codes.
    my %family;
    my %genus;
    my %familygenus;
    my %genera;
    my %families;
    # We need a list of language codes that includes the current language.
    # But the current language may not yet be in the data!
    my @lcodes = keys(%{$data});
    push(@lcodes, $config{lcode}) if(!exists($data->{$config{lcode}}));
    foreach my $lcode (@lcodes)
    {
        my $lhash = $languages->{$lname_by_code{$lcode}};
        $family{$lcode} = $lhash->{family};
        $genus{$lcode} = $lhash->{genus};
        $familygenus{$lcode} = $lhash->{familygenus};
        $families{$family{$lcode}}++;
        $genera{$genus{$lcode}}++;
    }
    my $myfamilygenus = $familygenus{$config{lcode}};
    my $myfamily = $family{$config{lcode}};
    my $mygenus = $genus{$config{lcode}};
    my $langgraph = read_language_graph();
    my $rank = rank_languages_by_proximity_to($config{lcode}, $langgraph, @lcodes);
    my $grank = rank_languages_by_proximity_to($mygenus, $langgraph, keys(%genera));
    my $frank = rank_languages_by_proximity_to($myfamily, $langgraph, keys(%families));
    @lcodes = sort
    {
        my $r = $frank->{$family{$a}} <=> $frank->{$family{$b}};
        unless($r)
        {
            $r = $family{$a} cmp $family{$b};
            unless($r)
            {
                $r = $grank->{$genus{$a}} <=> $grank->{$genus{$b}};
                unless($r)
                {
                    $r = $genus{$a} cmp $genus{$b};
                    unless($r)
                    {
                        $r = $rank->{$a} <=> $rank->{$b};
                        unless($r)
                        {
                            $r = $lname_by_code{$a} cmp $lname_by_code{$b};
                        }
                    }
                }
            }
        }
        $r
    }
    (@lcodes);
    my @lcodes_my_genus = grep {$_ ne $config{lcode} && $languages->{$lname_by_code{$_}}{familygenus} eq $myfamilygenus} (@lcodes);
    my @lcodes_my_family = grep {$languages->{$lname_by_code{$_}}{familygenus} ne $myfamilygenus && $languages->{$lname_by_code{$_}}{family} eq $myfamily} (@lcodes);
    my @lcodes_other = grep {$languages->{$lname_by_code{$_}}{family} ne $myfamily} (@lcodes);
    print("  <table>\n");
    print("    <tr><th colspan=2>Language</th><th>Total</th><th>Copula</th><th>Perfect</th><th>Future</th><th>Passive</th><th>Conditional</th><th>Necessitative</th><th>Potential</th><th>Desiderative</th><th>Other</th><th>Undocumented</th></tr>\n");
    foreach my $lcode ($config{lcode}, @lcodes_my_genus, @lcodes_my_family, @lcodes_other)
    {
        my @lemmas = sort(keys(%{$data->{$lcode}}));
        my @documented = grep {$data->{$lcode}{$_}{status} eq 'documented'} (@lemmas);
        my @undocumented = grep {$data->{$lcode}{$_}{status} ne 'documented'} (@lemmas);
        my @copula = grep {$data->{$lcode}{$_}{function} =~ m/^cop\./} (@documented);
        my @perfect = grep {$data->{$lcode}{$_}{function} eq 'Aspect=Perf'} (@documented);
        my @future = grep {$data->{$lcode}{$_}{function} eq 'Tense=Fut'} (@documented);
        my @passive = grep {$data->{$lcode}{$_}{function} eq 'Voice=Pass'} (@documented);
        my @conditional = grep {$data->{$lcode}{$_}{function} eq 'Mood=Cnd'} (@documented);
        my @necessitative = grep {$data->{$lcode}{$_}{function} eq 'Mood=Nec'} (@documented);
        my @potential = grep {$data->{$lcode}{$_}{function} eq 'Mood=Pot'} (@documented);
        my @desiderative = grep {$data->{$lcode}{$_}{function} eq 'Mood=Des'} (@documented);
        my @other = grep {$data->{$lcode}{$_}{function} !~ m/^(cop\.(AUX|PRON)|Aspect=Perf|Tense=Fut|Voice=Pass|Mood=(Cnd|Nec|Pot|Des))$/} (@documented);
        my $n = scalar(@documented)+scalar(@undocumented);
        print("    <tr><td>$lname_by_code{$lcode}</td><td>$lcode</td><td>$n</td>");
        print("<td>".join(' ', @copula)."</td>");
        print("<td>".join(' ', @perfect)."</td>");
        print("<td>".join(' ', @future)."</td>");
        print("<td>".join(' ', @passive)."</td>");
        print("<td>".join(' ', @conditional)."</td>");
        print("<td>".join(' ', @necessitative)."</td>");
        print("<td>".join(' ', @potential)."</td>");
        print("<td>".join(' ', @desiderative)."</td>");
        print("<td>".join(' ', @other)."</td>");
        print("<td>".join(' ', @undocumented)."</td></tr>\n");
    }
    print("  </table>\n");
}



#------------------------------------------------------------------------------
# Reads the graph of "neighboring" (geographically or genealogically)
# languages, genera, and families. Returns a reference to the graph (hash).
# Reads from a hardwired path.
#------------------------------------------------------------------------------
sub read_language_graph
{
    my %graph;
    open(GRAPH, 'langgraph.txt');
    while(<GRAPH>)
    {
        chomp;
        if(m/^(.+)----(.+)$/)
        {
            my $n1 = $1;
            my $n2 = $2;
            if($n1 ne $n2)
            {
                $graph{$n1}{$n2} = 1;
                $graph{$n2}{$n1} = 1;
            }
        }
        elsif(m/^(.+)--(\d+)--(.+)$/)
        {
            my $n1 = $1;
            my $d = $2;
            my $n2 = $3;
            if($n1 ne $n2)
            {
                $graph{$n1}{$n2} = $d;
                $graph{$n2}{$n1} = $d;
            }
        }
        else
        {
            print STDERR ("Unrecognized graph line '$_'\n");
        }
    }
    close(GRAPH);
    return \%graph;
}



#------------------------------------------------------------------------------
# Experimental sorting of languages by proximity to language X. We follow
# weighted edges in an adjacency graph read from an external file. The weights
# may ensure that all languages of the same genus are visited before switching
# to another genus, or the graph may only cover intra-genus relationships and
# the ranking provided by this function may be used as one of sorting criteria,
# the other being genus and family membership. The graph may also express
# relations among genera and families.
#------------------------------------------------------------------------------
sub rank_languages_by_proximity_to
{
    my $reflcode = shift; # language X
    my $graph = shift;
    my @lcodes = @_; # all language codes to sort (we need them only because some of them may not be reachable via the graph)
    # Sorting rules:
    # - first language X
    # - then other languages of the same genus
    # - then other languages of the same family
    # - then languages from other families
    # - within the same genus, proximity of languages can be controlled by
    #   a graph that we load from an external file
    # - similarly we can control proximity of genera within the same family
    # - similarly we can control proximity of families
    # - if two languages (genera, families) are at the same distance following
    #   the graph, they will be ordered alphabetically
    # Compute order of other languages when traversing from X
    # (roughly deep-first search, but observing distance from X and from the previous node at the same time).
    # The algorithm will not work well if the edge values do not satisfy the
    # triangle inequality but we do not check it.
    my %rank;
    my %done;
    my @queue = ($reflcode);
    my %qscore;
    my $current;
    my $lastrank = -1;
    while($current = shift(@queue))
    {
        # Sanity check.
        die "There is a bug in the program" if($done{$current});
        # Increase the score of all remaining nodes in the queue by my score (read as if we would have to return via the edge just traversed).
        foreach my $n (@queue)
        {
            $qscore{$n} += $qscore{$current};
        }
        delete($qscore{$current});
        $rank{$current} = ++$lastrank;
        if(exists($graph->{$current}))
        {
            my @neighbors = grep {!$done{$_}} (keys(%{$graph->{$current}}));
            # Add the neighbors to the queue if they are not already there.
            # Update there queue scores.
            foreach my $n (@neighbors)
            {
                push(@queue, $n) unless(scalar(grep {$_ eq $n} (@queue)));
                $qscore{$n} = $graph->{$current}{$n};
            }
            # Reorder the queue by the new scores.
            @queue = sort
            {
                my $r = $qscore{$a} <=> $qscore{$b};
                unless($r)
                {
                    $r = $a cmp $b;
                }
                $r
            }
            (@queue);
            #print STDERR ("LANGGRAPH DEBUG: $current --> ", join(', ', map {"$_:$qscore{$_}"} (@queue)), "\n");
        }
        $done{$current}++;
    }
    # Some languages may be unreachable via the graph. Make sure that they have
    # a defined rank too, and that their rank is higher than the rank of any
    # reachable language.
    foreach my $lcode (@lcodes)
    {
        if(!defined($rank{$lcode}))
        {
            $rank{$lcode} = $lastrank+1;
        }
    }
    return \%rank;
}



#------------------------------------------------------------------------------
# Reads the CGI parameters, checks their values and untaints them so that they
# can be safely used in the code. Untainting happens when the value is run
# through a regular expression. The untainted values are stored in a hash, and
# a reference to the hash is returned. The hash also contains an array
# reference under the key 'errors'. If a parameter contains unexpected
# characters, an error message will be added to the array and the value of the
# parameter will not be accepted. The caller may then decide whether or not to
# report the error and whether or not to treat it as fatal.
#------------------------------------------------------------------------------
sub get_parameters
{
    my $query = shift; # The CGI object that can supply the parameters.
    my $lname_by_code = shift; # hash ref
    my $functions = shift; # ref to array of pairs (arrays)
    my %config; # our hash where we store the parameters
    my @errors; # we store error messages about parameters here
    $config{errors} = \@errors;
    # Certain characters are not letters but they are used regularly between
    # letters in certain writing systems, hence they must be permitted.
    # ZERO WIDTH JOINER (\x{200D}) is category C (other); used in Devanagari, for instance.
    my $zwj = "\x{200D}";
    #--------------------------------------------------------------------------
    # Language code. If not provided, we show the introductory list of
    # languages.
    $config{lcode} = decode('utf8', $query->param('lcode'));
    if(!defined($config{lcode}) || $config{lcode} =~ m/^\s*$/)
    {
        $config{lcode} = '';
    }
    elsif($config{lcode} =~ m/^([a-z]{2,3})$/)
    {
        $config{lcode} = $1;
        if(!exists($lname_by_code->{$config{lcode}}))
        {
            push(@errors, "Unknown language code '$config{lcode}'");
        }
    }
    else
    {
        push(@errors, "Language code '$config{lcode}' does not consist of two or three lowercase English letters");
    }
    #--------------------------------------------------------------------------
    # Github user name. Some names may look like e-mail addresses.
    $config{ghu} = decode('utf8', $query->param('ghu'));
    if(!defined($config{ghu}) || $config{ghu} =~ m/^\s*$/)
    {
        $config{ghu} = '';
    }
    elsif($config{ghu} =~ m/^([-A-Za-z_0-9\@\.]+)$/)
    {
        $config{ghu} = $1;
    }
    else
    {
        push(@errors, "Unrecognized name '$config{ghu}'");
    }
    #--------------------------------------------------------------------------
    # Smart question is a primitive measure against robots that find the page
    # accidentally. Expected answer is "no".
    $config{smartquestion} = decode('utf8', $query->param('smartquestion'));
    if(!defined($config{smartquestion}) || $config{smartquestion} =~ m/^\s*$/)
    {
        $config{smartquestion} = '';
    }
    elsif($config{smartquestion} =~ m/^\s*no\s*$/i)
    {
        $config{smartquestion} = 'no';
    }
    else
    {
        push(@errors, "Unsatisfactory robotic response :-)");
    }
    #--------------------------------------------------------------------------
    # Lemma identifies the auxiliary that we are editing or going to edit.
    $config{lemma} = decode('utf8', $query->param('lemma'));
    if(!defined($config{lemma}) || $config{lemma} =~ m/^\s*$/)
    {
        $config{lemma} = '';
    }
    # Lemma can contain letters (L) and marks (M).
    # An example of a mark: U+94D DEVANAGARI SIGN VIRAMA.
    # We must also allow the hyphen, needed in Skolt Sami "i-ǥõl". (Jack Rueter: It is written with a hyphen. Historically it might be traced to a combination of the AUX:NEG ij and a reduced ǥõl stem derived from what is now the verb õlggâd ʹhave toʹ. The word-initial g has been retained in the fossilized contraction as ǥ, but that same word-initial letter has been lost in the standard verb.)
    # We must also allow the apostrophe, needed in Mbya Guarani "nda'ei" and "nda'ipoi".
    elsif($config{lemma} =~ m/^\s*([-\pL\pM']+)\s*$/) #'
    {
        $config{lemma} = $1;
    }
    else
    {
        push(@errors, "Lemma '$config{lemma}' contains non-letter characters");
    }
    #--------------------------------------------------------------------------
    # Function is a descriptive text (e.g. "Periphrastic aspect: perfect")
    # taken from a pre-defined list of options.
    $config{function} = decode('utf8', $query->param('function'));
    if(!defined($config{function}) || $config{function} =~ m/^\s*$/)
    {
        $config{function} = '';
    }
    else
    {
        if($config{function} =~ m/^(.+)$/)
        {
            $config{function} = $1;
        }
        # Verify that the function is one of the functions we defined.
        my @found = grep {$_->[1] eq $config{function}} (@{$functions});
        my $n = scalar(@found);
        if($n > 0)
        {
            if($n > 1)
            {
                print STDERR ("Something is wrong. Multiple functions listed in the source code equal to '$config{function}'.\n");
            }
        }
        else
        {
            push(@errors, "Unrecognized function '$config{function}'");
        }
    }
    #--------------------------------------------------------------------------
    # Rule is a descriptive text (e.g. "combination of the auxiliary with
    # a participle of the main verb"). It is not restricted to a pre-defined
    # set of options but it should not need more than English letters, spaces,
    # and some basic punctuation.
    $config{rule} = decode('utf8', $query->param('rule'));
    if(!defined($config{rule}) || $config{rule} =~ m/^\s*$/)
    {
        $config{rule} = '';
    }
    elsif($config{rule} =~ m/^([-A-Za-z \.:\(,;\)]+)$/)
    {
        $config{rule} = $1;
    }
    else
    {
        push(@errors, "Rule '$config{rule}' contains characters other than English letters, space, period, comma, semicolon, colon, hyphen, and round brackets");
    }
    #--------------------------------------------------------------------------
    # Deficient [paradigm] is a descriptive text that justifies a copula if
    # there are multiple lemmas of copula in one language.
    $config{deficient} = decode('utf8', $query->param('deficient'));
    if(!defined($config{deficient}) || $config{deficient} =~ m/^\s*$/)
    {
        $config{deficient} = '';
    }
    elsif($config{deficient} !~ m/\pL{3}/)
    {
        push(@errors, "Explanation of deficient copula paradigm '$config{deficient}' contains too few letters.");
    }
    elsif($config{deficient} =~ m/^([-A-Za-z \.:\(,;\)]+)$/)
    {
        $config{deficient} = $1;
    }
    else
    {
        push(@errors, "Explanation of deficient copula paradigm '$config{deficient}' contains characters other than English letters, space, period, comma, semicolon, colon, hyphen, and round brackets");
    }
    #--------------------------------------------------------------------------
    # Example in the original language may contain letters (including Unicode
    # letters), spaces, punctuation (including Unicode punctuation). Square
    # brackets have a special meaning, they mark the word we focus on. We
    # probably do not need < > & "" and we could ban them for safety (but
    # it is not necessary if we make sure to always escape them when inserting
    # them in HTML we generate). We may need the apostrophe in some languages,
    # though.
    $config{example} = decode('utf8', $query->param('example'));
    if(!defined($config{example}) || $config{example} =~ m/^\s*$/)
    {
        $config{example} = '';
    }
    else
    {
        # Remove duplicate, leading and trailing spaces.
        $config{example} =~ s/^\s+//;
        $config{example} =~ s/\s+$//;
        $config{example} =~ s/\s+/ /sg;
        if($config{example} !~ m/^[\pL\pM$zwj\pN\pP ]+$/)
        {
            push(@errors, "Example '$config{example}' contains characters other than letters, numbers, punctuation and space");
        }
        elsif($config{example} =~ m/[<>&"]/) # "
        {
            push(@errors, "Example '$config{example}' contains less-than, greater-than, ampersand or the ASCII quote");
        }
        # All characters that are allowed in a lemma must be allowed inside the square brackets.
        # In addition, we now also allow the ZERO WIDTH JOINER.
        elsif($config{example} !~ m/\[[-\pL\pM$zwj']+\]/) #'
        {
            push(@errors, "Example '$config{example}' does not contain a sequence of letters enclosed in [square brackets]");
        }
        if($config{example} =~ m/^(.+)$/)
        {
            $config{example} = $1;
        }
    }
    #--------------------------------------------------------------------------
    # English translation of the example is provided if the current language is
    # not English. We can probably allow the same regular expressions as for
    # the original example, although we typically do not need non-English
    # letters in the English translation.
    $config{exampleen} = decode('utf8', $query->param('exampleen'));
    if(!defined($config{exampleen}) || $config{exampleen} =~ m/^\s*$/)
    {
        $config{exampleen} = '';
    }
    else
    {
        # Remove duplicate, leading and trailing spaces.
        $config{exampleen} =~ s/^\s+//;
        $config{exampleen} =~ s/\s+$//;
        $config{exampleen} =~ s/\s+/ /sg;
        if($config{exampleen} !~ m/^[\pL\pM$zwj\pN\pP ]+$/)
        {
            push(@errors, "Example translation '$config{exampleen}' contains characters other than letters, numbers, punctuation and space");
        }
        elsif($config{exampleen} =~ m/[<>&"]/) # "
        {
            push(@errors, "Example translation '$config{exampleen}' contains less-than, greater-than, ampersand or the ASCII quote");
        }
        if($config{exampleen} =~ m/^(.+)$/)
        {
            $config{exampleen} = $1;
        }
    }
    #--------------------------------------------------------------------------
    # Comment is an optional English text. Since it may contain a word from the
    # language being documented, we should allow everything that is allowed in
    # the example.
    $config{comment} = decode('utf8', $query->param('comment'));
    if(!defined($config{comment}) || $config{comment} =~ m/^\s*$/)
    {
        $config{comment} = '';
    }
    else
    {
        # Remove duplicate, leading and trailing spaces.
        $config{comment} =~ s/^\s+//;
        $config{comment} =~ s/\s+$//;
        $config{comment} =~ s/\s+/ /sg;
        if($config{comment} !~ m/^[\pL\pM$zwj\pN\pP ]+$/)
        {
            push(@errors, "Comment '$config{comment}' contains characters other than letters, numbers, punctuation and space");
        }
        elsif($config{comment} =~ m/[<>&"]/) # "
        {
            push(@errors, "Comment '$config{comment}' contains less-than, greater-than, ampersand or the ASCII quote");
        }
        if($config{comment} =~ m/^(.+)$/)
        {
            $config{comment} = $1;
        }
    }
    #--------------------------------------------------------------------------
    # The parameter 'save' comes from the Save button which submitted the form.
    $config{save} = decode('utf8', $query->param('save'));
    if(!defined($config{save}))
    {
        $config{save} = 0;
        $config{savenew} = 0;
    }
    elsif($config{save} =~ m/^Save$/)
    {
        $config{save} = 1;
        $config{savenew} = 0;
    }
    elsif($config{save} =~ m/^Save new$/)
    {
        $config{save} = 1;
        $config{savenew} = 1;
    }
    else
    {
        push(@errors, "Unrecognized save button '$config{save}'");
    }
    #--------------------------------------------------------------------------
    # The parameter 'add' comes from the buttons that launch the form to add
    # a new auxiliary (separate buttons for copula and other auxiliaries).
    $config{add} = decode('utf8', $query->param('add'));
    if(!defined($config{add}))
    {
        $config{add} = 0;
        $config{addcop} = 0;
        $config{addnoncop} = 0;
    }
    elsif($config{add} =~ m/^Add copula$/)
    {
        $config{addcop} = 1;
        $config{add} = 1;
        $config{addnoncop} = 0;
    }
    elsif($config{add} =~ m/^Add (other|non-copula)$/)
    {
        $config{addnoncop} = 1;
        $config{add} = 1;
        $config{addcop} = 0;
    }
    else
    {
        push(@errors, "Unrecognized add button '$config{add}'");
    }
    return %config;
}



#------------------------------------------------------------------------------
# Reads the list of auxiliaries from an excerpt from the Python source code
# of the validator. This function is needed temporarily until we move the data
# to a separate JSON file.
#------------------------------------------------------------------------------
sub read_auxiliaries_from_python
{
    my %data;
    my $datafile = "$path/data.txt";
    # We need a buffer because some lists are spread across several lines.
    my $buffer = '';
    open(DATA, $datafile) or die("Cannot read '$datafile': $!");
    while(<DATA>)
    {
        # Remove the line break.
        s/\r?\n$//;
        # Skip comments.
        next if(m/^\s*\#/);
        s/\#.*//;
        $buffer .= $_;
        # A data line looks like this:
        # 'en':  ['be', 'have', 'do', 'will', 'would', 'may', 'might', 'can', 'could', 'shall', 'should', 'must', 'get', 'ought'],
        # Spaces are not interesting and line breaks can be harmful. Remove them.
        $buffer =~ s/\s//gs;
        if($buffer =~ m/'([a-z]{2,3})':\[('.+?'(?:,'.+?')*)\]/)
        {
            my $lcode = $1;
            my $auxlist = $2;
            if(!exists($lname_by_code{$lcode}))
            {
                die "Encountered unknown language code '$lcode' when reading the auxiliary list from Python";
            }
            my @auxlist = ();
            while($auxlist =~ s/^'(.+?)'//)
            {
                my $lemma = $1;
                push(@auxlist, $lemma);
                $auxlist =~ s/^\s*,\s*//;
            }
            # Create a record for each auxiliary. All fields that we want to
            # fill in the future are empty now, except for the lemma.
            my %hash;
            foreach my $lemma (@auxlist)
            {
                my %record =
                (
                    'function'    => '',
                    'rule'        => '',
                    'deficient'   => '',
                    'example'     => '',
                    'exampleen'   => '',
                    'comment'     => '',
                    'status'      => 'undocumented',
                    'lastchanged' => '',
                    'lastchanger' => ''
                );
                $hash{$lemma} = \%record;
            }
            if(exists($data{$lcode}))
            {
                die("Duplicate auxiliary list for language '$lcode' in the Python source");
            }
            $data{$lcode} = \%hash;
            # Empty the buffer.
            ###!!! Ignore the possibility that a new list starts on the same line.
            $buffer = '';
        }
    }
    close(DATA);
    return %data;
}



#------------------------------------------------------------------------------
# Reads the data about auxiliaries from the JSON file.
#------------------------------------------------------------------------------
sub read_data_json
{
    my $functions = shift; ###!!!
    my %data;
    my $datafile = "$path/data.json";
    my $json = json_file_to_perl($datafile);
    # The $json structure should contain two items, 'WARNING' and 'auxiliaries';
    # the latter should be a reference to an array of hashes.
    if(exists($json->{auxiliaries}) && ref($json->{auxiliaries}) eq 'ARRAY')
    {
        foreach my $record (@{$json->{auxiliaries}})
        {
            my $lcode = $record->{lcode};
            my $lemma = $record->{lemma};
            if(!exists($lname_by_code{$lcode}))
            {
                die("Unknown language code '$lcode' in the JSON file");
            }
            # We do not have to copy the data item by item to a new record.
            # We can simply copy the reference to the record (possibly after
            # erasing the language code inside).
            delete($record->{lcode});
            delete($record->{lemma});
            $data{$lcode}{$lemma} = $record;
        }
    }
    else
    {
        die("No auxiliaries found in the JSON file");
    }
    return %data;
}



#------------------------------------------------------------------------------
# Dumps the data as a JSON file.
#------------------------------------------------------------------------------
sub write_data_json
{
    # Initially, the data is read from the Python code.
    # This will change in the future and we will read the JSON file instead!
    my $data = shift;
    my $filename = shift;
    my $json = '{"WARNING": "Please do not edit this file manually. Such edits will be overwritten without notice. Go to http://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_auxiliary.pl instead.",'."\n\n";
    $json .= '"auxiliaries": ['."\n";
    my @jsonrecords = ();
    # Sort the list so that git diff is informative when we investigate changes.
    my @lcodes = sort(keys(%{$data}));
    foreach my $lcode (@lcodes)
    {
        my @lemmas = sort(keys(%{$data->{$lcode}}));
        foreach my $lemma (@lemmas)
        {
            my @record =
            (
                ['lcode'       => $lcode],
                ['lemma'       => $lemma],
                ['function'    => $data->{$lcode}{$lemma}{function}],
                ['rule'        => $data->{$lcode}{$lemma}{rule}],
                ['deficient'   => $data->{$lcode}{$lemma}{deficient}],
                ['example'     => $data->{$lcode}{$lemma}{example}],
                ['exampleen'   => $data->{$lcode}{$lemma}{exampleen}],
                ['comment'     => $data->{$lcode}{$lemma}{comment}],
                ['status'      => $data->{$lcode}{$lemma}{status}],
                ['lastchanged' => $data->{$lcode}{$lemma}{lastchanged}],
                ['lastchanger' => $data->{$lcode}{$lemma}{lastchanger}]
            );
            push(@jsonrecords, encode_json(@record));
        }
    }
    $json .= join(",\n", @jsonrecords)."\n";
    $json .= "]}\n";
    open(JSON, ">$filename") or die("Cannot write '$filename': $!");
    print JSON ($json);
    close(JSON);
}



#------------------------------------------------------------------------------
# Takes a list of pairs [name, value] and returns the corresponding JSON
# structure {"name1": "value1", "name2": "value2"}. The pair is an arrayref;
# if there is a third element in the array and it says "numeric", then the
# value is treated as numeric, i.e., it is not enclosed in quotation marks.
# The type in the third position can be also "list of structures" and
# "list of numeric".
#------------------------------------------------------------------------------
sub encode_json
{
    my @json = @_;
    # Encode JSON.
    my @json1 = ();
    foreach my $pair (@json)
    {
        my $name = '"'.$pair->[0].'"';
        my $value;
        if(defined($pair->[2]))
        {
            if($pair->[2] eq 'numeric')
            {
                $value = $pair->[1];
            }
            elsif($pair->[2] eq 'list')
            {
                # Assume that each list element is a string.
                my @array_json = ();
                foreach my $element (@{$pair->[1]})
                {
                    my $element_json = $element;
                    $element_json = escape_json_string($element_json);
                    $element_json = '"'.$element_json.'"';
                    push(@array_json, $element_json);
                }
                $value = '['.join(', ', @array_json).']';
            }
            elsif($pair->[2] eq 'list of numeric')
            {
                # Assume that each list element is numeric.
                my @array_json = ();
                foreach my $element (@{$pair->[1]})
                {
                    push(@array_json, $element);
                }
                $value = '['.join(', ', @array_json).']';
            }
            elsif($pair->[2] eq 'list of structures')
            {
                # Assume that each list element is a structure.
                my @array_json = ();
                foreach my $element (@{$pair->[1]})
                {
                    my $element_json = encode_json(@{$element});
                    push(@array_json, $element_json);
                }
                $value = '['.join(', ', @array_json).']';
            }
            else
            {
                log_fatal("Unknown value type '$pair->[2]'.");
            }
        }
        else # value is a string
        {
            if(!defined($pair->[1]))
            {
                die("Unknown value of attribute '$name'");
            }
            $value = $pair->[1];
            $value = escape_json_string($value);
            $value = '"'.$value.'"';
        }
        push(@json1, "$name: $value");
    }
    my $json = '{'.join(', ', @json1).'}';
    return $json;
}



#------------------------------------------------------------------------------
# Takes a string and escapes characters that would prevent it from being used
# in JSON. (For control characters, it throws a fatal exception instead of
# escaping them because they should not occur in anything we export in this
# block.)
#------------------------------------------------------------------------------
sub escape_json_string
{
    my $string = shift;
    # https://www.ietf.org/rfc/rfc4627.txt
    # The only characters that must be escaped in JSON are the following:
    # \ " and control codes (anything less than U+0020)
    # Escapes can be written as \uXXXX where XXXX is UTF-16 code.
    # There are a few shortcuts, too: \\ \"
    $string =~ s/\\/\\\\/g; # escape \
    $string =~ s/"/\\"/g; # escape " # "
    if($string =~ m/[\x{00}-\x{1F}]/)
    {
        log_fatal("The string must not contain control characters.");
    }
    return $string;
}



#------------------------------------------------------------------------------
# Escapes HTML control characters in a string.
#------------------------------------------------------------------------------
sub htmlescape
{
    my $x = shift;
    $x =~ s/&/&amp;/g;
    $x =~ s/</&lt;/g;
    $x =~ s/>/&gt;/g;
    return $x;
}
