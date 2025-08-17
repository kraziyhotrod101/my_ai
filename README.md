AI UI for Ollama on Linux
👋 Say Hello to my_ai!
Run awesome AI models right on your computer. It's free, it's private, and it's super easy thanks to Ollama.

So, what's my_ai all about? It's a simple, cool desktop app that lets you chat with large language models (LLMs) without sending your data to the cloud. It's all powered by Ollama, a fantastic tool that makes running AI locally a total breeze. This means your chats stay on your machine, just for your eyes. Pretty neat, right?

✨ The Cool Stuff
Here's why you'll love my_ai:

Totally Private! Your conversations are your business. They never, ever leave your computer.

Powered by Ollama: This is the tool that does all the heavy lifting. It's a favorite in the AI world for a reason—it just works.

Super Easy to Use: No command-line wizardry required! my_ai gives you a clean, simple chat interface.

Tons of Models: Wanna try Llama 3.3? Or maybe Gemma 2? Go for it! There's a huge library of open-source models ready for you to explore.

Works Offline: Once you've downloaded a model, you're good to go. No internet? No problem!

Free and Open Source: Yep, you read that right. It's completely free, and you can even help make it better.

🚀 Let's Get You Started
Ready to give it a spin? Here's what you need to do. It's pretty straightforward, I promise!

What You'll Need
First, you'll need to install Ollama. It's the engine that runs everything.

macOS: Get it here

Windows: Grab the preview version here

Linux: Open your terminal and paste this little line of code:

curl -fsSL https://ollama.com/install.sh | sh

You'll also need the Flutter SDK to build and run the app. You can find instructions for your operating system on the official site: Flutter Installation Guide

A decent computer! LLMs can be a bit hungry.

Minimum: 8 GB of RAM for smaller models like Mistral.

Better: 16 GB or more will let you play with bigger, smarter models.

Don't worry, it'll automatically use your graphics card (GPU) if you have one to make things even faster.

The Steps
Clone the Repo: Open your terminal and paste these two lines:

git clone https://github.com/your-username/my_ai.git
cd my_ai

Install the App Stuff:

flutter pub get

Run It!

flutter run

And that's it! my_ai should pop up on your screen and connect to Ollama. Easy peasy.

🤖 A Quick Note on Models
So, how do you get the models? my_ai will actually handle the downloads for you when you select a model in the app. But if you want to be a pro and do it yourself, you can use the terminal.

Just head over to the Ollama Model Library to see what's out there. Find a model you like, then type ollama pull [model-name]. For example:

ollama pull llama3.3

This will download the llama3.3 model, and it'll be ready for you to use in the app!

🤝 Wanna Help Out?
We'd love that! my_ai is a community project. If you find a bug, have a cool idea for a new feature, or just want to help with the writing, your contributions are more than welcome.

Check out the CONTRIBUTING.md file to see how you can jump in.

📄 The Legal Bits
This project is licensed under the MIT License. You can find all the details in the LICENSE file.

🙏 Big Thanks!
A huge shout-out to the folks behind Ollama for creating the amazing tool that makes this all possible.

And to the whole open-source AI community—you rock!
