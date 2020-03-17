defmodule Nebulex do
  @moduledoc ~S"""
  Nebulex is split into 2 main components:

    * `Nebulex.Cache` - caches are wrappers around the in-memory data store.
      Via the cache, we can put, get, update, delete and query existing entries.
      A cache needs an adapter to communicate to the in-memory data store.

    * `Nebulex.Decorators` - decorators provide an elegant way of annotating
      functions to be cached or evicted. By means of these decorators, it is
      possible the implementation of cache usage patterns like **Read-through**,
      **Write-through**, **Cache-as-SoR**, etc.

  In the following sections, we will provide an overview of those components and
  how they interact with each other. Feel free to access their respective module
  documentation for more specific examples, options and configuration.

  If you want to quickly check a sample application using Nebulex, please check
  the [getting started guide](http://hexdocs.pm/nebulex/getting-started.html).

  ## Caches

  `Nebulex.Cache` is the wrapper around the Cache. We can define a
  cache as follows:

      defmodule MyApp.MyCache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local,
          backend: :shards
      end

  Where the configuration for the Cache must be in your application
  environment, usually defined in your `config/config.exs`:

      config :my_app, MyApp.MyCache,
        gc_interval: 3600,
        partitions: 2

  Each cache in Nebulex defines a `start_link/1` function that needs to be
  invoked before using the cache. In general, this function is not called
  directly, but used as part of your application supervision tree.

  If your application was generated with a supervisor (by passing `--sup`
  to `mix new`) you will have a `lib/my_app/application.ex` file containing
  the application start callback that defines and starts your supervisor.
  You just need to edit the `start/2` function to start the repo as a
  supervisor on your application's supervisor:

      def start(_type, _args) do
        children = [
          {MyApp.Cache, []}
        ]

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

  ## Decorators

  Decorators are a set of caching annotations to make easier the implementation
  of different [cache patterns](https://github.com/ehcache/ehcache3/blob/master/docs/src/docs/asciidoc/user/caching-patterns.adoc).

      defmodule MyApp.Accounts do
        use Nebulex.Decorators

        alias MyApp.Accounts.User
        alias MyApp.Cache
        alias MyApp.Repo

        @decorate cache(cache: Cache, key: {User, id}, opts: [ttl: 3600])
        def get_user!(id) do
          Repo.get!(User, id)
        end

        @decorate cache(cache: Cache, key: {User, [email: email]})
        def get_user_by_email!(email) do
          Repo.get_by!(User, email: email)
        end

        @decorate update(cache: Cache, key: {User, user.id})
        def update_user!(%User{} = user, attrs) do
          user
          |> User.changeset(attrs)
          |> Repo.update!()
        end

        @decorate evict(cache: Cache, keys: [{User, user.id}, {User, [email: user.email]}])
        def delete_user(%User{} = user) do
          Repo.delete(user)
        end
      end

  It also provides a decorator to define hooked functions, a way to support
  pre/post hooks. See `Nebulex.Decorators` for more information.
  """
end
