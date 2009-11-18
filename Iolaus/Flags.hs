-- Copyright (C) 2002-2004 David Roundy
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2, or (at your option)
-- any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; see the file COPYING.  If not, write to
-- the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
-- Boston, MA 02110-1301, USA.

module Iolaus.Flags ( Flag( .. ), Compression( .. ), compression,
                    want_external_merge, isInteractive ) where
import Iolaus.RepoPath ( AbsolutePath, AbsolutePathOrStd )

-- | The 'Flag' type is a list of all flags that can ever be
-- passed to iolaus, or to one of its commands.
data Flag = Help | ListOptions | NoTest | Test | Build | TestParents
          | NoCauterizeAllHeads | CauterizeAllHeads | CommutePast Int
          | DeltaDebugWorkingSubset | RecordFor String
          | NoTagOnTest | TagOnTest | Nice | NotNice
               | HelpOnMatch | OnlyChangesToFiles
               | LeaveTestDir | NoLeaveTestDir
               | Timings | Debug | DebugVerbose
               | Verbose | NormalVerbosity | Quiet
               | Target String | Cc String
               | Output AbsolutePathOrStd | OutputAutoName AbsolutePath
               | Subject String | InReplyTo String
               | SendmailCmd String | Author String | PatchName String
               | OnePatch String | SeveralPatch String
               | AfterPatch String | UpToPatch String
               | TagName String | LastN Int | PatchIndexRange Int Int
               | NumberPatches | MaxC Int
               | OneTag String | AfterTag String | UpToTag String
               | Count
               | LogFile AbsolutePath | RmLogFile
               | DistName String | All
               | Recursive | NoRecursive | Reorder
               | RestrictPaths | DontRestrictPaths
               | LookForAdds | NoLookForAdds | AnyOrder
               | Intersection | Union | Complement
               | Sign | SignAs String | NoSign | SignSSL String
               | Verify AbsolutePath
               | EditDescription | NoEditDescription
               | Toks String
               | EditLongComment | NoEditLongComment | PromptLongComment
               | AllowConflicts | MarkConflicts | NoAllowConflicts
               | Boring | AllowCaseOnly | AllowWindowsReserved
               | Compress | NoCompress | UnCompress
               | NativeMerge | IolausMerge | IolausSloppyMerge
               | FirstParentMerge
               | WorkDir String | RepoDir String | RemoteRepo String
               | Reply String | ApplyAs String
               | Interactive
               | DiffCmd String
               | ExternalMerge String | Summary | NoSummary
               | ShowMerges | HideMerges
               | ShowParents | ShowHash | NoShowHash | ShowTested | HideTested
               | Unified | Reverse | Graph
               | Complete | Lazy | Ephemeral
               | FixFilePath AbsolutePath AbsolutePath | DiffFlags String
               | XMLOutput
               | NonApply | NonVerify
               | DryRun | ConfigDefault | GlobalConfig | SystemConfig
               | Disable
               | Sibling AbsolutePath | Relink | NoLinks
               | Files | NoFiles | Directories | NoDirectories
               | UMask String
               | StoreInMemory
               | AllowUnrelatedRepos
               | NullFlag
                 deriving ( Eq, Show )

data Compression = NoCompression | GzipCompression
compression :: [Flag] -> Compression
compression f | NoCompress `elem` f = NoCompression
              | otherwise = GzipCompression

want_external_merge :: [Flag] -> Maybe String
want_external_merge [] = Nothing
want_external_merge (ExternalMerge c:_) = Just c
want_external_merge (_:fs) = want_external_merge fs

isInteractive :: [Flag] -> Bool
isInteractive = isInteractive_ True
    where
      isInteractive_ def [] = def
      isInteractive_ _ (Interactive:_) = True
      isInteractive_ _ (All:_) = False
      isInteractive_ _ (DryRun:fs) = isInteractive_ False fs
      isInteractive_ def (_:fs) = isInteractive_ def fs

