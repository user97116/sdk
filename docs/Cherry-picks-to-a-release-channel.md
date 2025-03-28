# Cherry-picks to a Release Channel

Cherry-picking is the process of selecting and merging an existing bug fix from our main development branch into a release branch (e.g. from `main` to `beta` or `stable`) for inclusion into the next hotfix release.

**Note**: This process applies to bugs and regressions. Feature work is not considered for cherry picking and will need to wait for the next release.

## Notice a cherry-pick is required

Resolve the issue and land the fix on the main branch along with tests to
confirm whether the issue was in fact fixed. Identity whether the latest beta
and stable releases contain the issue and judge whether the fix should be
backported. Two changelists may be required if both channels are affected.

## How to cherry-pick a changelist

Cherry-pick your changelist's commit onto a new branch targeting beta or stable:

```console
$ git fetch
$ git new-branch --upstream origin/stable cherry    # or origin/beta
$ git cherry-pick --edit $commit
$ $EDITOR CHANGELOG.md     # stable only, see below
```

Update the commit message accordingly:

1. Add a `[beta]` or `[stable]` gerrit hashtag at the start of the first line.
2. Rename the `Reviewed-on` field to `Cherry-pick` to link to the original
   changelist being cherry-picked.\
3. Remove the conflicting fields `Change-id`, `Commit-queue`, `Reviewed-by` that
   are not true of the new changelist.
4. Fill out the changelist description with the following information:
   1. Issue description: (Brief description of the issue. What is the issue?
      What platforms are the problems occurring on?)
   2. What is the fix: (Brief description of the fix)
   3. Why cherry-pick: (Describe the reasons, impacted users and functional
      issues to explain why this should be cherry-picked.)
   4. Risk: (Describe the risks associated with this cherry-pick.)
   5. Issue link(s): (Add links to the original issues fixed by this
      cherry-pick.)

E.g.:

```
[stable] Fix foo crash.

Issue description: When attempting to use foo under certain conditions, users are unable to
compile.
What is the fix: foo is now evaluated at runtime.
Why cherry-pick: Users of foo are no longer able to compile to bar.
Risk: Low, this fix has landed on the main channel and is tested on the same infrastructure. 
Issue link(s): https://github.com/dart-lang/sdk/issues/12345678

Cherry-pick: https://dart-review.googlesource.com/c/sdk/+/12345678
```

## Changelog

Stable cherry-picks [must have CHANGELOG.md entries](Gerrit-Submit-Requirements#changelog)
explaining the changes. The release engineers don't have your full context and rely on this
information.

Beta releases don't have changelog entries.

If the `CHANGELOG.md` does not already have a section for the next stable
hotfix, add such a section and increase the patch number (e.g. `3.0.4` ->
`3.0.5`) without a date. If a section has a release date, it has already been
released and should not be modified. The date will be added when the stable
release is authored and it is decided when the release will be published.

```markdown
## 3.0.5

This is a patch release that:

- Fixes all bugs in the Dart SDK (issue [#123456])

[#123456]: https://dart-review.googlesource.com/c/sdk/+/123456

## 3.0.4
**Released on:** 2025-01-08

This is a patch release that:

...
```

If the cherry-pick is infrastructure only and is invisible to users, the
`Changelog-Exempt: ...` footer exempts the change from the changelog
requirement.

## Uploading the cherry-pick changelist

Upload the changelist to gerrit for approval:

```console
git cl upload
```

Trigger a commit queue dry run and add any appropriate try builders to confirm
the fix is correct.

## Submitting the cherry-pick

Once the cherry-pick changelist is reviewed by an area subject matter expert and
a Dart team lead, the cherry-pick author will submit it to the commit queue. The
tryjobs will compare the test results with the previous commit on the
beta/stable branch and fail if any regressions are introduced. If any
regressions must be introduced, or the try builders don't work on the older
beta/stable code, then bypass the commit queue by force submitting.

## Cherry-picking a commit in a dependency

If you need to cherry pick a single commit (here `$commit-to-cherry-pick`) in a dependency (here `third-party/pkg/pub`) to a release-channel (here `beta`).

First in the SDK checkout, find the current revision at the release branch:

```
dart-sdk/sdk/ > git checkout beta && git pull
dart-sdk/sdk/ > gclient getdep -r sdk/third_party/pkg/pub
a3f8b2fd36ec432450caf907474a02023ef3e44e
```

Now in a clone of the dependency, create a cherry-pick on a new branch, and push it to the origin repo:
```
pub/ > git checkout -b cherry-pick a3f8b2fd36ec432450caf907474a02023ef3e44e
pub/ > git cherry-pick $commit-to-cherry-pick
pub/ > git push -u origin cherry_pick:cherry_pick
pub/ > git rev-parse HEAD
6d1857c84cfb8a014aefedaf2d453214bf5ddb96 # <-- this is the revision we want to move to.
```

Wait a little while for the change to be mirrored to [dart.googlesource.com](https://dart.googlesource.com/).

We need to ensure that the cherry-picked commit on the dependency gets merged into the protected branch (here `main`). Otherwise there is a risk it will be GC'ed.

The following script creates such a merge:

```
#!/bin/bash
BRANCH="<name of branch to merge>"
REPO="<name of repository>"

# Defaults that may need to be changed.
TARGET_BRANCH="main" # sometimes repositories use a different default branch.
ORG="dart-lang" # most dependencies are in dart-lang, but not all.
REMOTE=origin # use upstream if that is the target repo's remote.

# Clone the repo if you don't already have a clone.
gh repo clone "$ORG/$REPO"

# Switch to the repo's directory.
cd "$REPO"

# Fetch and create a branch tracking the target branch.
git fetch "$REMOTE"
git switch -c "merge-$BRANCH" "$REMOTE/$TARGET_BRANCH"

# Create a merge commit.
git merge -sours "$REMOTE/$BRANCH"
gh pr create
```

Now create a PR for this merge, and make sure to "merge" instead of "squash" it (you might have to temporarily change repo settings to do this).

Now, go back to the SDK checkout, create a bump-commit and a CL that moves the release-channel to the new cherry-pick commit (not the merge) using the manage-deps tool:

```
dart-sdk/sdk/ > tools/manage_deps.dart bump third_party/pkg/pub --target=6d1857c84cfb8a014aefedaf2d453214bf5ddb96
```

Update the CL to be relative to the release-channel:

```
dart-sdk/sdk/ > git branch --set-upstream-to=origin/beta
dart-sdk/sdk/ > git cl upload
```

This CL can be used in the cherry-pick flow above.
