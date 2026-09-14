{
  version = "0.7.1";

  source = {
    owner = "nestybox";
    repo = "sysbox";
    rev = "82881aaaf2ce22ad0ff81487f458162908cb933f";
    hash = "sha256-eB/UYUyWsr0X57YJe/8llStKcDqIz26QynqP+ypGhso=";
    fetchSubmodules = true;
  };

  # Gitlinks recorded by sysbox@82881aa; the components have no v0.7.1 tags.
  components = {
    sysbox-runc = {
      rev = "081856cc5d17e7095f066b08d0eca6bb0b515c47";
      vendorHash = "sha256-8jUYuh7RJH3hiFA6xkCaxtcxmWxVnMfZRVKLxlhBPls=";
    };
    sysbox-mgr = {
      rev = "2d45af01bcfd8641e6641f76104c6003bf501cd7";
      vendorHash = "sha256-FhyVLGx0SCZn9i3NkfJDj+P7ao+qncu690/zfzf9CHI=";
    };
    sysbox-fs = {
      rev = "c3d2ebc65102e32e74e383675f03b45556326888";
      vendorHash = "sha256-M6XqcIPqiz1hbeYLe2PMXx3y885xd0tT2O4sPoveDpc=";
    };
  };
}
