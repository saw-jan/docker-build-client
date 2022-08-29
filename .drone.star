def main(ctx):
  versions = [
    '2.9',
    'latest',
    'source',
    'fedora',
  ]

  arches = [
    'amd64',
  ]

  config = {
    'version': None,
    'arch': None,
    'trigger': [],
    'repo': ctx.repo.name
  }

  stages = []

  for version in versions:
    config['version'] = version

    if config['version'] in ['latest', 'source', 'fedora']:
      config['path'] = config['version']
    else:
      config['path'] = 'v%s' % config['version']

    m = manifest(config)
    inner = []

    for arch in arches:
      config['arch'] = arch

      if config['version'] == 'latest':
        config['tag'] = arch
      elif config['version'] == 'fedora':
        config['tag'] = '%s-%s-%s' % (ctx.build.commit[0:8], config['version'], arch)
      else:
        config['tag'] = '%s-%s' % (config['version'], arch)

      if config['arch'] == 'amd64':
        config['platform'] = 'amd64'

      if config['arch'] == 'arm64v8':
        config['platform'] = 'arm64'

      if config['arch'] == 'arm32v7':
        config['platform'] = 'arm'

      config['internal'] = '%s-%s' % (ctx.build.commit, config['tag'])

      d = docker(config)
      m['depends_on'].append(d['name'])

      inner.append(d)

    inner.append(m)
    stages.extend(inner)

  return stages

def docker(config):
  return {
    'kind': 'pipeline',
    'type': 'docker',
    'name': '%s-%s' % (config['arch'], config['path']),
    'platform': {
      'os': 'linux',
      'arch': config['platform'],
    },
    'steps': steps(config),
    'image_pull_secrets': [
      'registries',
    ],
    'depends_on': [],
    'trigger': {
      'ref': [
        'refs/heads/master',
        'refs/pull/**',
      ],
    },
  }

def manifest(config):
  return {
    'kind': 'pipeline',
    'type': 'docker',
    'name': 'manifest-%s' % config['path'],
    'platform': {
      'os': 'linux',
      'arch': 'amd64',
    },
    'steps': [
      {
        'name': 'manifest',
        'image': 'plugins/manifest',
        'settings': {
          'username': {
            'from_secret': 'public_username',
          },
          'password': {
            'from_secret': 'public_password',
          },
          'spec': '%s/manifest.tmpl' % config['path'],
          'ignore_missing': 'true',
        },
      },
    ],
    'depends_on': [],
    'trigger': {
      'ref': [
        'refs/heads/master',
        'refs/tags/**',
      ],
    },
  }

def dryrun(config):
  return [{
    'name': 'dryrun',
    'image': 'plugins/docker',
    'settings': {
      'dry_run': True,
      'tags': config['tag'],
      'dockerfile': '%s/Dockerfile.%s' % (config['path'], config['arch']),
      'repo': 'sawjan/desktop-client',
      'context': config['path'],
    },
    'when': {
      'ref': [
        'refs/pull/**',
      ],
    },
  }]

def publish(config):
  return [{
    'name': 'publish',
    'image': 'plugins/docker',
    'settings': {
      'username': 'sawjan',
      'password': {
        'from_secret': 'public_password',
      },
      'tags': config['tag'],
      'dockerfile': '%s/Dockerfile.%s' % (config['path'], config['arch']),
      'repo': 'sawjan/desktop-client',
      'context': config['path'],
      'pull_image': False,
    },
    'when': {
      'ref': [
        'refs/heads/master',
        'refs/tags/**',
      ],
    },
  }]

def steps(config):
  return dryrun(config) + publish(config)
