#!/usr/bin/env php
<?php
/**
 * resolve_version.php
 *
 * Reads the sources.json index, filters Joomla entries, and resolves the best
 * download URL matching the requested version specifier.
 *
 * Usage:
 *   php resolve_version.php <path-to-sources.json> <version-request>
 *
 * version-request can be:
 *   latest   — latest stable release (no alpha/beta/rc)
 *   5        — latest stable 5.x.x
 *   5.2      — latest stable 5.2.x
 *   5.2.1    — exact version 5.2.1
 *
 * Output (stdout, one line):
 *   <resolved-version>|<download-url>
 *
 * Exits with a non-zero code and error message on stderr on failure.
 */

if ($argc !== 3) {
    fwrite(STDERR, "Usage: resolve_version.php <sources.json> <version-request>\n");
    exit(1);
}

$sourcesFile    = $argv[1];
$versionRequest = trim($argv[2]);

if (!is_file($sourcesFile) || !is_readable($sourcesFile)) {
    fwrite(STDERR, "ERROR: Cannot read sources file: {$sourcesFile}\n");
    exit(1);
}

$json = file_get_contents($sourcesFile);
$all  = json_decode($json, true);

if (!is_array($all)) {
    fwrite(STDERR, "ERROR: sources.json is not valid JSON.\n");
    exit(1);
}

// Keep only Joomla CMS entries
$entries = array_filter($all, static function (array $entry): bool {
    return isset($entry['cms']) && strtolower($entry['cms']) === 'joomla'
        && isset($entry['version'], $entry['url']);
});

if (empty($entries)) {
    fwrite(STDERR, "ERROR: No Joomla entries found in sources.json.\n");
    exit(1);
}

/**
 * Returns true if the version string looks like a stable release
 * (no alpha, beta, rc, dev suffixes).
 */
function isStable(string $version): bool
{
    return !preg_match('/alpha|beta|rc|dev/i', $version);
}

/**
 * Compare two version strings using version_compare.
 * Returns 1 if $a > $b, -1 if $a < $b, 0 if equal.
 */
function cmpVersion(string $a, string $b): int
{
    return version_compare($a, $b);
}

/**
 * Given a list of candidate entries (each with 'version' and 'url'),
 * pick the one with the highest version, preferring tar.zst > tar.bz2 > tar.gz > zip.
 */
function pickBest(array $candidates): ?array
{
    if (empty($candidates)) {
        return null;
    }

    // Group by version
    $byVersion = [];
    foreach ($candidates as $entry) {
        $byVersion[$entry['version']][] = $entry;
    }

    // Find highest version
    $versions = array_keys($byVersion);
    usort($versions, 'cmpVersion');
    $best = end($versions);

    // Among entries for this version, pick best archive format
    $formatPriority = ['tar.zst' => 3, 'tar.bz2' => 2, 'tar.gz' => 1, 'zip' => 0];

    $chosen    = null;
    $chosenPri = -1;

    foreach ($byVersion[$best] as $entry) {
        $url = $entry['url'];
        $pri = 0;

        foreach ($formatPriority as $ext => $p) {
            if (stripos($url, $ext) !== false || stripos($url, str_replace('.', '-', $ext)) !== false) {
                $pri = $p;
                break;
            }
        }

        if ($pri > $chosenPri) {
            $chosen    = $entry;
            $chosenPri = $pri;
        }
    }

    return $chosen;
}

// Filter by version request
$lower = strtolower($versionRequest);

if ($lower === 'latest') {
    $candidates = array_filter($entries, static fn($e) => isStable($e['version']));
} elseif (preg_match('/^\d+$/', $versionRequest)) {
    // Major only, e.g. "5"
    $candidates = array_filter(
        $entries,
        static fn($e) => isStable($e['version'])
            && strpos($e['version'], $versionRequest . '.') === 0
    );
} elseif (preg_match('/^\d+\.\d+$/', $versionRequest)) {
    // Major.minor, e.g. "5.2"
    $candidates = array_filter(
        $entries,
        static fn($e) => isStable($e['version'])
            && strpos($e['version'], $versionRequest . '.') === 0
    );
} elseif (preg_match('/^\d+\.\d+\.\d+/', $versionRequest)) {
    // Exact version (may or may not be stable — honour what the user asked for)
    $normalised = preg_replace('/[^0-9.]/', '', $versionRequest); // strip any trailing junk
    $candidates = array_filter(
        $entries,
        static fn($e) => version_compare($e['version'], $normalised, '==')
    );
} else {
    fwrite(STDERR, "ERROR: Unrecognised version request '{$versionRequest}'.\n");
    exit(1);
}

$result = pickBest(array_values($candidates));

if ($result === null) {
    fwrite(STDERR, "ERROR: No Joomla release found matching '{$versionRequest}'.\n");
    exit(1);
}

echo $result['version'] . '|' . $result['url'] . "\n";
exit(0);
