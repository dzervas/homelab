[
  {
    name: 'kube',
    allow: [
      'kubectl (-n \\w+ )?(get|describe|logs) ',
    ],
    deny: [
      'kubectl (-n \\w+ )?get secrets ',
    ],
  },
]
