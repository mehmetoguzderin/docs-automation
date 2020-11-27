#!/usr/bin/env perl
# Scans the UD docs repository for documentation of features.
# Copyright © 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use YAML qw(LoadFile);

# At present, the path to the local copy of docs is hardwired.
my $docs = 'C:/Users/Dan/Documents/Lingvistika/Projekty/universal-dependencies/docs';
my %hash;
my %lhash;
# Scan globally documented features.
# Some of them are officially part of the universal guidelines.
# The rest are technically language-specific but individual languages do not have to document them individually.
my @ufeats = qw(Abbr Animacy Aspect Case Clusivity Definite Degree Evident Foreign Gender Mood NounClass Number NumType Person Polarity Polite Poss PronType Reflex Tense Typo VerbForm Voice);
my $gdfeats = "$docs/_u-feat";
opendir(DIR, $gdfeats) or die("Cannot read folder '$gdfeats': $!");
my @gdfiles = grep {m/^.+\.md$/ && -f "$gdfeats/$_"} (readdir(DIR));
closedir(DIR);
foreach my $file (@gdfiles)
{
    my $feature = $file;
    $feature =~ s/\.md$//;
    # Layered features have [brackets] in the name but the file name uses a hyphen and no brackets.
    $feature =~ s/^([A-Za-z0-9]+)-([a-z]+)$/$1\[$2\]/;
    if(grep {$_ eq $feature} (@ufeats))
    {
        $hash{$feature}{type} = 'universal';
    }
    else
    {
        $hash{$feature}{type} = 'global';
    }
    if($feature !~ m/^[A-Z][A-Za-z0-9]*(\[[a-z]+\])?$/)
    {
        push(@{$hash{$feature}{errors}}, "Feature name '$feature' does not have the prescribed form.");
    }
    read_feature_doc("$gdfeats/$file", \%{$hash{$feature}});
}
# Scan locally documented (language-specific) features.
opendir(DIR, $docs) or die("Cannot read folder '$docs': $!");
my @langfolders = sort(grep {m/^_[a-z]{2,3}$/ && -d "$docs/$_/feat"} (readdir(DIR)));
closedir(DIR);
foreach my $langfolder (@langfolders)
{
    my $lcode = $langfolder;
    $lcode =~ s/^_//;
    my $ldfeats = "$docs/$langfolder/feat";
    opendir(DIR, $ldfeats) or die("Cannot read folder '$ldfeats': $!");
    my @ldfiles = grep {m/^.+\.md$/ && -f "$ldfeats/$_"} (readdir(DIR));
    closedir(DIR);
    foreach my $file (@ldfiles)
    {
        my $feature = $file;
        $feature =~ s/\.md$//;
        # Layered features have [brackets] in the name but the file name uses a hyphen and no brackets.
        $feature =~ s/^([A-Za-z0-9]+)-([a-z]+)$/$1\[$2\]/;
        if(grep {$_ eq $feature} (@ufeats))
        {
            $lhash{$lcode}{$feature}{type} = 'universal';
        }
        else
        {
            $lhash{$lcode}{$feature}{type} = 'local';
        }
        if($feature !~ m/^[A-Z][A-Za-z0-9]*(\[[a-z]+\])?$/)
        {
            push(@{$lhash{$lcode}{$feature}{errors}}, "Feature name '$feature' does not have the prescribed form.");
        }
        read_feature_doc("$ldfeats/$file", $lhash{$lcode}{$feature});
    }
}
# Print an overview of the features we found.
#print_markdown_overview(\%hash, \%lhash);
print_json(\%hash, \%lhash, $docs);



#------------------------------------------------------------------------------
# Reads a MarkDown file that documents one feature.
#------------------------------------------------------------------------------
sub read_feature_doc
{
    my $filepath = shift;
    my $feathash = shift; # hash reference
    my $udver = 1;
    my @values = ();
    my %valdoc;
    my $current_value;
    my @unrecognized_example_lines;
    #print STDERR ("Reading $filepath\n");
    open(FILE, $filepath) or die("Cannot read file '$filepath': $!");
    while(<FILE>)
    {
        chomp();
        s/\s+$//;
        # The following line should occur in the MarkDown header (between two '---' lines).
        # We take the risk and do not check where exactly it occurs.
        if(m/^udver:\s*'(\d+)'$/)
        {
            $udver = $1;
        }
        # Feature values will be recognized only if they have a section heading in the prescribed form.
        if(m/^\#\#\#\s*<a\s+name="(.+?)"\s*>`\1`<\/a>:\s*(.+)$/)
        {
            my $value = $1;
            my $short_description = $2;
            if(defined($current_value) && $valdoc{$current_value}{examples} == 0)
            {
                push(@{$feathash->{errors}}, "No examples found under value '$current_value'.", @unrecognized_example_lines);
            }
            if(exists($valdoc{$value}))
            {
                push(@{$feathash->{errors}}, "Multiple definition of value '$value'.");
            }
            else
            {
                $current_value = $value;
                @unrecognized_example_lines = ();
                push(@values, $value);
                $valdoc{$value}{shortdesc} = $short_description;
            }
            if($value !~ m/^[A-Z0-9][A-Za-z0-9]*$/)
            {
                push(@{$feathash->{errors}}, "Feature value '$value' does not have the prescribed form.");
            }
        }
        # Warn about unrecognized level 3 headings.
        # Note that there are some examples of legitimate level 3 headings that are not feature values.
        # References is one such case. The "Prague Dependency Treebank" exception is needed if there is a Diff section (level 2) with treebanks that currently differ from the overall guidelines.
        elsif(m/^\#\#\#[^\#]/ && !m/^\#\#\#\s*(References|Prague Dependency Treebank)$/)
        {
            push(@{$feathash->{errors}}, "Unrecognized level 3 heading '$_'.");
        }
        # Check whether examples are given for each value.
        if(m/^(\#\#\#\#\s*)?Examples?:?/)
        {
            if(defined($current_value))
            {
                $valdoc{$current_value}{examples}++;
            }
        }
        elsif(m/examples/i)
        {
            # We will report this as an error only if we have not found an actual Examples heading.
            push(@unrecognized_example_lines, "Unrecognized examples '$_'.");
        }
    }
    close(FILE);
    if(defined($current_value) && $valdoc{$current_value}{examples} == 0)
    {
        push(@{$feathash->{errors}}, "No examples found under value '$current_value'.", @unrecognized_example_lines);
    }
    if($udver != 2)
    {
        push(@{$feathash->{errors}}, "Documentation does not belong to UD v2 guidelines.");
    }
    if(scalar(@values)==0)
    {
        push(@{$feathash->{errors}}, "No feature values found.");
    }
    $feathash->{values} = \@values;
    $feathash->{valdoc} = \%valdoc;
}



#------------------------------------------------------------------------------
# Prints an overview of all documented features (as well as errors in the
# format of documentation), formatted using MarkDown syntax.
#------------------------------------------------------------------------------
sub print_markdown_overview
{
    my $ghash = shift; # ref to hash with global features
    my $lhash = shift; # ref to hash with local features
    my @features = sort(keys(%{$ghash}));
    print("# Universal features\n\n");
    foreach my $feature (grep {$ghash->{$_}{type} eq 'universal'} (@features))
    {
        print("* [$feature](https://universaldependencies.org/u/feat/$feature.html)\n");
        foreach my $value (@{$ghash->{$feature}{values}})
        {
            print('  * value `'.$value.'`: '.$ghash->{$feature}{valdoc}{$value}{shortdesc}."\n");
        }
        foreach my $error (@{$ghash->{$feature}{errors}})
        {
            print('  * <span style="color:red">ERROR: '.$error.'</span>'."\n");
        }
    }
    print("\n");
    print("# Globally documented non-universal features\n\n");
    foreach my $feature (grep {$ghash->{$_}{type} eq 'global'} (@features))
    {
        my $file = $feature;
        $file =~ s/^([A-Za-z0-9]+)\[([a-z]+)\]$/$1-$2/;
        print("* [$feature](https://universaldependencies.org/u/feat/$file.html)\n");
        foreach my $value (@{$ghash->{$feature}{values}})
        {
            print('  * value `'.$value.'`: '.$ghash->{$feature}{valdoc}{$value}{shortdesc}."\n");
        }
        foreach my $error (@{$ghash->{$feature}{errors}})
        {
            print('  * <span style="color:red">ERROR: '.$error.'</span>'."\n");
        }
    }
    print("\n");
    print("# Locally documented language-specific features\n\n");
    my @lcodes = sort(keys(%{$lhash}));
    my $n = scalar(@lcodes);
    print("The following $n languages seem to have at least some documentation of features: ".join(' ', map {"$_ (".scalar(keys(%{$lhash->{$_}})).")"} (@lcodes))."\n");
    print("\n");
    foreach my $lcode (@lcodes)
    {
        print("## $lcode\n\n");
        my @features = sort(keys(%{$lhash->{$lcode}}));
        foreach my $feature (@features)
        {
            my $file = $feature;
            $file =~ s/^([A-Za-z0-9]+)\[([a-z]+)\]$/$1-$2/;
            print("* [$feature](https://universaldependencies.org/$lcode/feat/$file.html)\n");
            foreach my $value (@{$lhash->{$lcode}{$feature}{values}})
            {
                print('  * value `'.$value.'`: '.$lhash->{$lcode}{$feature}{valdoc}{$value}{shortdesc}."\n");
            }
            foreach my $error (@{$lhash->{$lcode}{$feature}{errors}})
            {
                print('  * <span style="color:red">ERROR: '.$error.'</span>'."\n");
            }
        }
        print("\n");
    }
}



#------------------------------------------------------------------------------
# Prints a JSON structure with documented feature-value pairs for each UD
# language.
#------------------------------------------------------------------------------
sub print_json
{
    my $ghash = shift; # ref to hash with global features
    my $lhash = shift; # ref to hash with local features
    # We need to know the list of all UD languages first.
    my $docspath = shift;
    my $languagespath = "$docspath/../docs-automation/codes_and_flags.yaml";
    my $languages = LoadFile($languagespath);
    if( !defined($languages) )
    {
        die "Cannot read the list of languages";
    }
    my @lcodes = sort(map {$languages->{$_}{lcode}} (keys(%{$languages})));
    print("{\n");
    my @jsonlines = ();
    foreach my $lcode (@lcodes)
    {
        my @fvpairs = ();
        # Add locally defined (or redefined) features.
        if(exists($lhash->{$lcode}))
        {
            foreach my $feature (sort(keys(%{$lhash->{$lcode}})))
            {
                # Skip the feature if there are errors in its documentation.
                unless(scalar(@{$lhash->{$lcode}{$feature}{errors}}) > 0)
                {
                    foreach my $value (sort(@{$lhash->{$lcode}{$feature}{values}}))
                    {
                        push(@fvpairs, "$feature=$value");
                    }
                }
            }
        }
        # Add globally defined features that are not redefined locally.
        foreach my $feature (sort(keys(%{$ghash})))
        {
            unless(exists($lhash->{$lcode}{$feature}))
            {
                # Skip the feature if there are errors in its documentation.
                unless(scalar(@{$ghash->{$feature}{errors}}) > 0)
                {
                    foreach my $value (sort(@{$ghash->{$feature}{values}}))
                    {
                        push(@fvpairs, "$feature=$value");
                    }
                }
            }
        }
        push(@jsonlines, '"'.escape_json_string($lcode).'": ['.join(', ', map {'"'.escape_json_string($_).'"'} (@fvpairs)).']');
    }
    print(join(",\n", @jsonlines)."\n");
    print("}\n");
}



#------------------------------------------------------------------------------
# Takes a list of pairs [name, value] and returns the corresponding JSON
# structure {"name1": "value1", "name2": "value2"}. The pair is an arrayref;
# if there is a third element in the array and it says "numeric", then the
# value is treated as numeric, i.e., it is not enclosed in quotation marks.
# The type in the third position can be also "list" (of strings),
# "list of numeric" and "list of structures".
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