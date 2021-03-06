# Iolaus to-do list

- Add delta debugging support for commits.  Essentially git bisect,
  but allowing for new merges, so we get a whole lot more potential
  combinations.

- Somehow allow record --record-for REPO to not always contact remote
  repo, so record will work offline (and be faster with a high-latency
  connection).  One problem is that of how to deal with situations
  where the --record-for is not a defined remote (e.g. --record-for
  git@github.com/droundy/iolaus).  The other is that of figuring out
  when to update the cached remote head information, since the
  --record-for may differ from the origin, pull repo, push repo, etc.
  In short, record may be the *only* scenario in which we interact
  with this particular remote, so *never* contacting the remote on
  record doesn't sound like such a hot idea.

- Make new repositories (gotten by get) have --record-for set!

- Add support (and documentation) for proper git-style hooks.

- Add proper support (and documentation) for proper git-style color
  configuration.  We're already part of the way there, but there's no
  support for the mechanism for turning color off.  The default will
  be color, however.

- Add support for signing and verification of tags.

- Work out a more sophisticated review mechanism, possibly involving a
  new command "review", which will display a commit, and allow the
  user to create a new commit which depends only on that one commit
  and makes no changes.  The idea would be that a trunk could restrict
  itself to only pull signed "review" commits (which must, of course,
  be by a different developer than the commit that is reviewed), thus
  ensuring that every patch is looked at by at least one developer.
  This could work in tandem with the --intersection scheme to allow a
  truly distributed approach to code review.

- Create framework in which TODO items could be associated with bugs
  and test scripts, to encourage creation of test scripts when adding
  TODO items.

- Consider adding a yaml patch type and diff.  This could be useful
  for avoiding conflicts in the above TODO list idea.  Possibly we
  could work at the intersection of markdown and yaml.  e.g. the
  existing TODO.md file is a markdown file that is also (almost?) a
  valid yaml file.  It might be useful to support precisely this
  intersection.  I'm not sure how many different sorts of characters
  would require quoting in order to make a list markdown file also
  parse as a list yaml file, but it might be pretty cool.  It also
  might be something that we could easily recognize in the diff
  process and automatically treat differently.  Currently the only way
  to truly be safe from spurious dependencies in things like TODO
  items and bugs is to make each item a separate file, which is pretty
  silly.  For a few things it makes sense (probably for test scripts),
  but for most others, it's much nicer to be able to work with a
  single file.

- Fix mergeCommits.  Currently, we just merge a bunch of "big" diffs,
  which are simply sequences of named primitive patches.  This gives
  us trouble when some of these commits involve conflict resolution.
  Somehow, we're not seeing the conflict as resolved.  I think the
  key is to actually go ahead and let the merge algorithm know about
  the commit structure, rather than simply flattening everything into
  a single sequence of primitive patches.  :(
