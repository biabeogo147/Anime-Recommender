from langchain.chains import RetrievalQA
from src.prompt_template import get_anime_prompt
from langchain_google_genai import ChatGoogleGenerativeAI

class AnimeRecommender:
    def __init__(self, retriever, api_key: str, model_name: str):
        self.llm = ChatGoogleGenerativeAI(model=model_name, google_api_key=api_key)
        self.prompt = get_anime_prompt()

        self.qa_chain = RetrievalQA.from_chain_type(
            llm = self.llm,
            chain_type = "stuff",
            retriever = retriever,
            return_source_documents = True,
            chain_type_kwargs = {"prompt":self.prompt}
        )

    def get_recommendation(self,query:str):
        result = self.qa_chain({"query":query})
        return result['result']