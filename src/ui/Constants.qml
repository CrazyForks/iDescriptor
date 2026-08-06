// SPDX-FileCopyrightText: 2025-2026 Uncore <https://github.com/uncor3>
// SPDX-License-Identifier: AGPL-3.0-or-later

pragma Singleton
import QtQml

QtObject {
    readonly property string repoUrl: "https://github.com/iDescriptor/iDescriptor"
    readonly property string linkedinUrl: "https://www.linkedin.com/company/idescriptor/"
    readonly property string redditUrl: "https://www.reddit.com/r/iDescriptor/"
    readonly property string openCollectiveUrl: "https://opencollective.com/idescriptor"
    readonly property string githubSponsorsUrl: "https://github.com/sponsors/iDescriptor"

    // FIXME: change when the sponsors file is merged into the main branch.
    readonly property string sponsorsUrl: "https://raw.githubusercontent.com/iDescriptor/iDescriptor/refs/heads/dev/sponsors.json"
}
