local k = import 'k.libsonnet';


{
  withAccess(name): k.networking.v1.networkPolicy
                    .new(name).spec.withIngress([
    {
      from: [
        {
          podSelector: {
            matchLabels: {
              app: 'my-app',
            },
          },
        },
      ],
    },
  ]),
}
