const fs = require('fs');
const path = require('path');

function normalizeText(value) {
  return String(value || '').trim();
}

function normalizeKey(value) {
  return normalizeText(value).toLowerCase();
}

function ensureArray(value) {
  return Array.isArray(value) ? value : [];
}

function inferReleaseBump(value) {
  const key = normalizeKey(value);
  if (key.includes('major')) {
    return 'major';
  }
  if (key.includes('minor')) {
    return 'minor';
  }
  if (key.includes('patch')) {
    return 'patch';
  }
  return '';
}

function inferIssueType(value) {
  const key = normalizeKey(value);
  if (key.includes('bug')) {
    return 'bug';
  }
  if (key.includes('enhancement')) {
    return 'enhancement';
  }
  return '';
}

function loadLabelContract(contractPath) {
  const resolvedPath = path.resolve(contractPath);
  if (!fs.existsSync(resolvedPath)) {
    throw new Error(`Label contract not found: ${resolvedPath}`);
  }

  const raw = fs.readFileSync(resolvedPath, 'utf8');
  const contract = JSON.parse(raw);
  contract.labels = ensureArray(contract.labels);
  contract.aliases = ensureArray(contract.aliases);
  return contract;
}

function getCanonicalLabelSet(contract) {
  return new Set(
    ensureArray(contract.labels)
      .map((entry) => normalizeText(entry.name))
      .filter(Boolean)
  );
}

function buildReleaseTypeToCanonicalMap(contract) {
  const map = new Map();
  for (const entry of ensureArray(contract.labels)) {
    if (normalizeKey(entry.category) !== 'release_increment') {
      continue;
    }
    const bump = normalizeKey(entry.bump_type) || inferReleaseBump(entry.name);
    const name = normalizeText(entry.name);
    if (!bump || !name) {
      continue;
    }
    if (!map.has(bump)) {
      map.set(bump, name);
    }
  }
  return map;
}

function buildIssueTypeToCanonicalMap(contract) {
  const map = new Map();
  for (const entry of ensureArray(contract.labels)) {
    if (normalizeKey(entry.category) !== 'issue_type') {
      continue;
    }
    const issueType = normalizeKey(entry.issue_type) || inferIssueType(entry.name);
    const name = normalizeText(entry.name);
    if (!issueType || !name) {
      continue;
    }
    if (!map.has(issueType)) {
      map.set(issueType, name);
    }
  }
  return map;
}

function buildReleaseLabelMap(contract) {
  const releaseTypeToCanonical = buildReleaseTypeToCanonicalMap(contract);
  const map = new Map();

  for (const entry of ensureArray(contract.labels)) {
    if (normalizeKey(entry.category) !== 'release_increment') {
      continue;
    }
    const bump = normalizeKey(entry.bump_type) || inferReleaseBump(entry.name);
    const canonicalName = normalizeText(entry.name);
    if (!bump || !canonicalName) {
      continue;
    }

    map.set(normalizeKey(canonicalName), bump);
    for (const alias of ensureArray(entry.aliases)) {
      const aliasName = normalizeText(alias);
      if (!aliasName) {
        continue;
      }
      map.set(normalizeKey(aliasName), bump);
    }
  }

  for (const entry of ensureArray(contract.aliases)) {
    if (normalizeKey(entry.category) !== 'release_increment') {
      continue;
    }

    const aliasName = normalizeText(entry.name);
    const canonicalName = normalizeText(entry.canonical_name);
    const bump =
      normalizeKey(entry.bump_type) ||
      inferReleaseBump(canonicalName) ||
      inferReleaseBump(aliasName);
    if (!aliasName || !bump) {
      continue;
    }

    map.set(normalizeKey(aliasName), bump);
    if (canonicalName) {
      map.set(normalizeKey(canonicalName), bump);
      if (!releaseTypeToCanonical.has(bump)) {
        releaseTypeToCanonical.set(bump, canonicalName);
      }
    }
  }

  return map;
}

function buildIssueTypeLabelMap(contract) {
  const issueTypeToCanonical = buildIssueTypeToCanonicalMap(contract);
  const map = new Map();

  for (const entry of ensureArray(contract.labels)) {
    if (normalizeKey(entry.category) !== 'issue_type') {
      continue;
    }
    const issueType = normalizeKey(entry.issue_type) || inferIssueType(entry.name);
    const canonicalName = normalizeText(entry.name);
    if (!issueType || !canonicalName) {
      continue;
    }

    map.set(normalizeKey(canonicalName), issueType);
    for (const alias of ensureArray(entry.aliases)) {
      const aliasName = normalizeText(alias);
      if (!aliasName) {
        continue;
      }
      map.set(normalizeKey(aliasName), issueType);
    }
  }

  for (const entry of ensureArray(contract.aliases)) {
    if (normalizeKey(entry.category) !== 'issue_type') {
      continue;
    }

    const aliasName = normalizeText(entry.name);
    const canonicalName = normalizeText(entry.canonical_name);
    const issueType =
      normalizeKey(entry.issue_type) ||
      inferIssueType(canonicalName) ||
      inferIssueType(aliasName);
    if (!aliasName || !issueType) {
      continue;
    }

    map.set(normalizeKey(aliasName), issueType);
    if (canonicalName) {
      map.set(normalizeKey(canonicalName), issueType);
      if (!issueTypeToCanonical.has(issueType)) {
        issueTypeToCanonical.set(issueType, canonicalName);
      }
    }
  }

  return map;
}

function normalizeLabels(labelNames, map) {
  const matches = [];
  for (const rawName of ensureArray(labelNames)) {
    const raw = normalizeText(rawName);
    const normalized = map.get(normalizeKey(raw));
    if (raw && normalized) {
      matches.push({ raw, normalized });
    }
  }

  return {
    matches,
    normalized: [...new Set(matches.map((entry) => entry.normalized))],
    matchedRaw: [...new Set(matches.map((entry) => entry.raw))],
  };
}

function getExemptStaleLabels(contract) {
  return ensureArray(contract.labels)
    .filter((entry) => entry && entry.stale_exempt === true)
    .map((entry) => normalizeText(entry.name))
    .filter(Boolean);
}

module.exports = {
  loadLabelContract,
  getCanonicalLabelSet,
  buildReleaseTypeToCanonicalMap,
  buildIssueTypeToCanonicalMap,
  buildReleaseLabelMap,
  buildIssueTypeLabelMap,
  normalizeLabels,
  getExemptStaleLabels,
};
