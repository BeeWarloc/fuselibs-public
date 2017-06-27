using Uno;
using Uno.Collections;
using Uno.UX;

using Fuse.Internal;

namespace Fuse
{
	/**
		A common base class that adds nodes and resources to the parent node while active.
		
		[subclass Fuse.NodeGroupBase]
		
		Be aware there is no ordering between the Nodes, Resources, and Templates. These are each independent lists which have their own order.
	*/
	public abstract class NodeGroupBase : Behavior, ITemplateSource
	{
		RootableList<Node> _nodes;
		int NodeCount { get { return _nodes == null ? 0 : _nodes.Count; } }
		
		[UXContent]
		/**
			Nodes to add to the Parent when this trigger is any non-deactivated state (Progress > 0)
		*/
		public IList<Node> Nodes
		{
			get
			{
				if (_nodes == null) 
				{
					_nodes = new RootableList<Node>();
					if (IsRootingCompleted)
						_nodes.Subscribe(OnNodeAdded, OnNodeRemoved);
				}
				return _nodes;
			}
		}

		TemplateSourceImpl _templates;
		
		[UXContent]
		public IList<Template> Templates { get { return _templates.Templates; } }
		public Template FindTemplate(string key) { return _templates.FindTemplate(key); }
		
		internal NodeGroupBase() { }
		
		protected bool UseTemplates = true;
		
		bool _useContent = false;
		internal bool UseContent
		{
			get { return _useContent; }
			set
			{
				if (value == _useContent)
					return;
					
				_useContent = value;
				if (IsRootingStarted && _useContent)
					AddContent();
				else if (!_useContent)
					RemoveContent();
			}
		}
		
		protected virtual void OnNodeAdded(Node n)
		{
			if (IsRootingCompleted && UseContent)
			{
				//TODO: This is wrong and will not do the right thing. It needs to add only the new 'n' node
				RemoveContent();
				AddContent();
			}
		}

		protected virtual void OnNodeRemoved(Node n)
		{
			if (IsRootingCompleted && UseContent)
				Parent.BeginRemoveChild(n);
		}
		
		RootableList<Resource> _resources;

		[UXContent]
		public IList<Resource> Resources
		{
			get
			{
				if (_resources == null) 
				{
					_resources = new RootableList<Resource>();
					if (IsRootingCompleted)
						_resources.Subscribe(OnResourceAdded, OnResourceRemoved);
				}
				return _resources;
			}
		}

		void OnResourceAdded(Resource r)
		{
			if (IsRootingCompleted && UseContent)
			{
				Parent.Resources.Add(r);
			}
		}

		void OnResourceRemoved(Resource r)
		{
			if (IsRootingCompleted && UseContent)
				Parent.Resources.Remove(r);
		}

		protected override void OnRooted()
		{
			base.OnRooted();
			if (UseContent)
				AddContent();
				
			if (_nodes != null)
				_nodes.Subscribe(OnNodeAdded, OnNodeRemoved);
			if (_resources != null)
				_resources.Subscribe(OnResourceAdded, OnResourceRemoved);
		}
		
		protected override void OnUnrooted()
		{
			if (UseContent)
				RemoveContent();
				
			if (_nodes != null)
				_nodes.Unsubscribe();
			if (_resources != null)
				_resources.Unsubscribe();
			base.OnUnrooted();
		}

		//used to prevent double-adding and double-removing if a derived class changes the UseContent
		//state during rooting
		bool _contentAdded;
		MiniList<Node> _addedNodes;
		
		void AddContent()
		{
			if (_contentAdded)
				return;
			_contentAdded = true;
				
			if (Parent == null)
			{
				Fuse.Diagnostics.InternalError( "AddContent called prior to having a Parent", this );
				return;
			}

			if (_resources != null)
			{
				for (int i = 0; i < _resources.Count; i++) 
				{
					Parent.Resources.Add(_resources[i]);
				}
			}

			if (NodeCount == 0 && _templates.Count == 0)
				return;
				
			//add after the location of `this` in Parent
			int where = Parent.Children.IndexOf(this);
			if (where == -1)
			{
				Fuse.Diagnostics.InternalError( "Could not locate node in parent, content not added", this );
				return;
			}

			for (int i = 0; i < NodeCount; ++i)
			{
				var n = _nodes[i];
				n.OverrideContextParent = n.OverrideContextParent ?? this;
				_addedNodes.Add(n);
			}
			
			if (UseTemplates)
			{
				for (int i=0; i < _templates.Count; ++i)
				{
					var n = _templates[i].New() as Node;
					if (n == null)
					{
						Fuse.Diagnostics.InternalError( "Template contains a non-Node", this );
						continue;
					}
					n.OverrideContextParent = n.OverrideContextParent ?? this;
					_addedNodes.Add(n);
				}
			}
			
			Parent.InsertNodes( where, _addedNodes.GetEnumerator() );
		}

		void RemoveContent()
		{
			if (!_contentAdded)
				return;
			_contentAdded = false;
			
			if (Parent == null) return;

			if (_resources != null)
			{
				for (int i = 0; i < _resources.Count; i++) 
				{
					Parent.Resources.Remove(_resources[i]);
				}
			}

			for (int i=0; i < _addedNodes.Count; ++i)
			{
				var n = _addedNodes[i];
				if (n.OverrideContextParent == this) n.OverrideContextParent = null;
				Parent.BeginRemoveChild(n);
			}
			_addedNodes.Clear();
		}
	}

	/**
		Allows creating a class that contains several nodes and resources that are added directly to their Parent, as though included directly.
		
			<NodeGroup ux:Class="GridLine">
				<float4 ux:Property="Color"/>
				<string ux:Property="Title"/>
				<string ux:Property="Emoji"/>
				
				<Rectangle Color="{Property this.Color}"/>
				<Text Value="{Property this.Title}"/>
				<Text Value="{Property this.Emoji}"/>
			</NodeGroup>
			
			<Grid Columns="50,1*,auto" DefaultRow="auto">
				<GridLine Color="#AFA" Title="Happy One" Emoji="😀"/>
				<GridLine Color="#FFA" Title="Cry Baby" Emoji="😭"/>
				<GridLine Color="#FAA" Title="Mr. Angry" Emoji="😠"/>
			</Grid>
	*/
	public class NodeGroup : NodeGroupBase
	{
		/**
			When `true` (the default) the contained nodes and resources will be added to the parent node. When `false` they will be removed.
			
			Like a Visual, the templates added to the NodeGroup are not instantiated when rooted. They are made available for lookup in other classes that need a source, such as `Each.TemplateSource`.  You can use @Instance if you need to instantiate templates at rooting time.
		*/
		public bool IsActive
		{
			get { return UseContent; }
			set { UseContent = value; }
		}
		
		public NodeGroup()
		{
			UseTemplates = false;
			UseContent = true;
		}
	}
}
